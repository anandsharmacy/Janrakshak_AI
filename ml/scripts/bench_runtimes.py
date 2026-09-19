#!/usr/bin/env python
"""Inference-runtime benchmark: LightGBM (pandas / numpy / truncated) vs ONNX Runtime vs
Treelite-compiled C, on the real corridor matrix.

    # 1) export one day's corridor matrix (project env)
    python scripts/bench_runtimes.py export --date 2025-08-15 --out reports/stage11/corridor.npy
    # 2) benchmark (deploy env: lightgbm, onnxruntime, onnxmltools, treelite, tl2cgen)
    python scripts/bench_runtimes.py run --matrix reports/stage11/corridor.npy \
        --bundle deploy/bundles/current --out reports/stage11/runtimes.json

Each runtime runs in a FRESH subprocess, so load time and peak RSS are that
runtime's own and not an artefact of whatever was imported before it. Every runtime's
output on the full corridor is compared with LightGBM's native float64 prediction:
a runtime that is fast but ranks segments differently is not an optimization.
"""
from __future__ import annotations

import argparse
import json
import os
import resource
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RUNTIMES = ["lgb_pandas", "lgb_numpy", "lgb_numpy_t300", "onnxruntime", "treelite"]
BATCHES = [(1, 400), (100, 200), (1000, 60)]
THREADS = [1, 4, 8]


def _rss_mb() -> float:
    r = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return r / (1024 * 1024) if sys.platform == "darwin" else r / 1024


def _pct(times) -> dict:
    t = np.asarray(times) * 1000
    return {"p50_ms": float(np.percentile(t, 50)), "p95_ms": float(np.percentile(t, 95)),
            "p99_ms": float(np.percentile(t, 99)), "mean_ms": float(t.mean())}


# --------------------------------------------------------------------------- #
def load_runtime(name: str, bundle: Path, workdir: Path, schema: dict):
    """Return (predict(X, nthread) -> prob, artifact_bytes, load_seconds, notes)."""
    import lightgbm as lgb
    model_txt = bundle / "model.txt"
    notes = {}
    t0 = time.perf_counter()
    if name.startswith("lgb"):
        b = lgb.Booster(model_file=str(model_txt))
        k = 300 if name.endswith("t300") else None
        size = model_txt.stat().st_size
        if name == "lgb_pandas":
            import pandas as pd
            feats, cats = schema["features"], schema["categorical"]
            levels = schema["category_levels"]

            def to_frame(X):
                df = pd.DataFrame(X, columns=feats)
                for c in cats:
                    codes = np.nan_to_num(df[c].to_numpy(), nan=-1).astype(int)
                    df[c] = pd.Categorical.from_codes(codes, levels[c])
                return df
            fn = lambda X, nt: b.predict(to_frame(X), num_threads=nt)          # noqa: E731
            notes["input"] = "pandas DataFrame with categorical dtype (the training path)"
        else:
            fn = lambda X, nt: b.predict(X, num_threads=nt, num_iteration=k)   # noqa: E731
            notes["input"] = "numpy float64" + (f", first {k} trees" if k else "")
            if k:
                p = workdir / "t300.txt"
                b.save_model(str(p), num_iteration=k)
                size = p.stat().st_size
    elif name == "onnxruntime":
        import onnxruntime as ort
        from onnxmltools import convert_lightgbm
        from onnxmltools.convert.common.data_types import FloatTensorType
        b = lgb.Booster(model_file=str(model_txt))
        tc = time.perf_counter()
        onx = convert_lightgbm(b, initial_types=[("input", FloatTensorType([None, b.num_feature()]))],
                               zipmap=False, target_opset=15)
        p = workdir / "model.onnx"
        p.write_bytes(onx.SerializeToString())
        notes["convert_s"] = time.perf_counter() - tc
        size = p.stat().st_size
        sessions = {}

        def fn(X, nt):
            if nt not in sessions:
                so = ort.SessionOptions()
                so.intra_op_num_threads = nt if nt > 0 else 0
                so.inter_op_num_threads = 1
                sessions[nt] = ort.InferenceSession(str(p), so, providers=["CPUExecutionProvider"])
            s = sessions[nt]
            out = s.run(None, {"input": X.astype(np.float32)})
            prob = out[1] if len(out) > 1 else out[0]
            return np.asarray(prob)[:, 1] if np.ndim(prob) == 2 else np.asarray(prob)
        t0 = time.perf_counter()
        fn(np.zeros((1, b.num_feature()), np.float64), 1)
        notes["input"] = "float32 tensor (ONNX TreeEnsemble is float32 end to end)"
        notes["onnxruntime"] = ort.__version__
    elif name == "treelite":
        import tl2cgen
        import treelite
        tc = time.perf_counter()
        tm = treelite.frontend.load_lightgbm_model(str(model_txt))
        lib = workdir / ("model.dylib" if sys.platform == "darwin" else "model.so")
        tl2cgen.export_lib(tm, toolchain="clang" if sys.platform == "darwin" else "gcc",
                           libpath=str(lib), params={"parallel_comp": 8})
        notes["compile_s"] = time.perf_counter() - tc
        size = lib.stat().st_size
        preds = {}
        t0 = time.perf_counter()

        def fn(X, nt):
            if nt not in preds:
                preds[nt] = tl2cgen.Predictor(str(lib), nthread=max(1, nt or os.cpu_count()))
            out = preds[nt].predict(tl2cgen.DMatrix(X, dtype="float64"))
            return np.asarray(out).reshape(len(X), -1)[:, -1]
        fn(np.zeros((1, 45)), 1)
        notes["input"] = "float64 via tl2cgen.DMatrix; model compiled to native code"
        notes["treelite"] = treelite.__version__
    else:
        raise ValueError(name)
    return fn, size, time.perf_counter() - t0, notes


def worker(name: str, matrix: Path, bundle: Path, out_npy: Path) -> dict:
    schema = json.loads((bundle / "schema.json").read_text())
    X = np.load(matrix)
    rss0 = _rss_mb()
    with tempfile.TemporaryDirectory() as td:
        try:
            fn, size, load_s, notes = load_runtime(name, bundle, Path(td), schema)
        except Exception as e:                    # noqa: BLE001 — a failed conversion IS a result
            return {"runtime": name, "error": f"{type(e).__name__}: {e}"[:500]}
        res = {"runtime": name, "artifact_bytes": int(size), "load_s": load_s, **notes}
        full = fn(X, 0)
        np.save(out_npy, np.asarray(full, float))
        for bs, reps in BATCHES:
            ts = []
            for i in range(reps):
                j = (i * 7919) % (len(X) - bs)
                Xb = X[j:j + bs]
                t = time.perf_counter()
                fn(Xb, 1)
                ts.append(time.perf_counter() - t)
            res[f"batch_{bs}_1thread"] = _pct(ts)
        for nt in THREADS:
            ts = []
            for _ in range(5):
                t = time.perf_counter()
                fn(X, nt)
                ts.append(time.perf_counter() - t)
            med = float(np.median(ts))
            res[f"corridor_{nt}thread"] = {"median_s": med, "rows_per_s": int(len(X) / med)}
        res["peak_rss_mb"] = _rss_mb()
        res["rss_before_load_mb"] = rss0
    return res


def compare(ref: np.ndarray, p: np.ndarray) -> dict:
    d = np.abs(p - ref)
    k = int(0.01 * len(ref))
    top_r, top_p = set(np.argsort(-ref)[:k]), set(np.argsort(-p)[:k])
    rr, rp = ref.argsort().argsort(), p.argsort().argsort()
    return {"max_abs_diff": float(d.max()), "mean_abs_diff": float(d.mean()),
            "rows_diff_gt_1e-6": int((d > 1e-6).sum()), "rows_diff_gt_1e-3": int((d > 1e-3).sum()),
            "spearman": float(np.corrcoef(rr, rp)[0, 1]),
            "top1pct_overlap": len(top_r & top_p) / k}


def run(matrix: Path, bundle: Path, out: Path, only=None) -> None:
    """`only` re-measures a subset and merges it into an existing results file; the
    parity reference (lgb_numpy) is always re-run so comparisons stay same-process-fresh."""
    results, preds = [], {}
    names = RUNTIMES if not only else ["lgb_numpy"] + [n for n in only if n != "lgb_numpy"]
    with tempfile.TemporaryDirectory() as td:
        for name in names:
            npy = Path(td) / f"{name}.npy"
            cmd = [sys.executable, __file__, "worker", name, "--matrix", str(matrix),
                   "--bundle", str(bundle), "--pred", str(npy)]
            r = subprocess.run(cmd, capture_output=True, text=True)
            try:
                res = json.loads(r.stdout.strip().splitlines()[-1])
            except (IndexError, json.JSONDecodeError):
                res = {"runtime": name, "error": (r.stderr or r.stdout)[-800:]}
            if npy.exists():
                preds[name] = np.load(npy)
            print(json.dumps({k: v for k, v in res.items() if not isinstance(v, dict)}), flush=True)
            results.append(res)
        ref = preds.get("lgb_numpy")
        for res in results:
            if ref is not None and res["runtime"] in preds:
                res["parity_vs_lgb_numpy_f64"] = compare(ref, preds[res["runtime"]])
    import platform
    import lightgbm
    env = {"python": sys.version.split()[0], "lightgbm": lightgbm.__version__,
           "machine": platform.machine(), "platform": platform.platform(),
           "cpu_count": os.cpu_count(), "rows": int(np.load(matrix, mmap_mode="r").shape[0])}
    import treelite as _tl
    try:
        import tl2cgen as _tc
        env["treelite"], env["tl2cgen"] = _tl.__version__, _tc.__version__
    except ImportError:
        pass
    if only and out.exists():
        prev = json.loads(out.read_text())
        keep = [r for r in prev["results"] if r["runtime"] not in names]
        results = keep + results
        results.sort(key=lambda r: RUNTIMES.index(r["runtime"]))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"env": env, "results": results}, indent=1))


def export(date: str, out: Path) -> None:
    sys.path.insert(0, str(ROOT / "src"))
    from sih_ml.serve.bundle import Bundle
    from sih_ml.serve.featurestore import FeatureStore
    b = Bundle.load(ROOT / "deploy" / "bundles" / "current")
    st = FeatureStore.load(ROOT / "deploy" / "featurestore", b.schema)
    X = st.matrix(date)
    out.parent.mkdir(parents=True, exist_ok=True)
    np.save(out, X)
    print(json.dumps({"exported": str(out), "shape": list(X.shape)}))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export"); e.add_argument("--date", required=True); e.add_argument("--out", required=True)
    r = sub.add_parser("run"); r.add_argument("--matrix", required=True); r.add_argument("--bundle", required=True)
    r.add_argument("--out", required=True); r.add_argument("--only", nargs="*", default=None)
    w = sub.add_parser("worker"); w.add_argument("name"); w.add_argument("--matrix"); w.add_argument("--bundle")
    w.add_argument("--pred")
    a = ap.parse_args()
    if a.cmd == "export":
        export(a.date, Path(a.out))
    elif a.cmd == "run":
        run(Path(a.matrix), Path(a.bundle).resolve(), Path(a.out), a.only)
    else:
        print(json.dumps(worker(a.name, Path(a.matrix), Path(a.bundle), Path(a.pred)), default=str))
