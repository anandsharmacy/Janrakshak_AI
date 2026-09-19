"""Accuracy - speed - size trade-off, measured on the champion.

Stage 8 recorded when each inference optimization would become worth doing (e.g.
"pruning: revisit if per-request latency becomes user-facing, < 50 ms"). Stage 10
does not re-argue those thresholds; it measures the frontier so that the day one of
them trips, the trade is already quantified:

  * tree-count truncation — the GBDT analogue of pruning. Every fold model is scored
    at a fraction of its early-stopped round count on its own held-out blocks, so
    the accuracy side is measured out-of-fold, never on training rows.
  * size / latency at each truncation point on the full-dev artifact.
  * threads x batch size for one full corridor pass (309,042 segments).

Quantization and ONNX/Treelite/TensorRT are not measured: none of those toolchains
is installed, and installing one to confirm an optimization nobody needs would be
the cargo-cult Stage 8 declined.
"""
from __future__ import annotations

import tempfile
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score

from sih_ml.improve.candidate import BaggedModel


def _members(model) -> list:
    return model.models if isinstance(model, BaggedModel) else [model]


def _predict_k(model, X, frac: float, num_threads: int = 0) -> np.ndarray:
    out = []
    for m in _members(model):
        k = max(1, int(round(frac * (m.best_iteration_ or m.booster_.current_iteration()))))
        p = m.booster_.predict(X[m.features], num_iteration=k, num_threads=num_threads)
        if getattr(m, "raw_score_", False):
            p = 1.0 / (1.0 + np.exp(-np.clip(p, -50, 50)))
        out.append(p)
    return np.mean(out, axis=0)


def truncation_frontier(data, res: dict, fracs=(0.1, 0.25, 0.5, 0.75, 1.0)) -> pd.DataFrame:
    rows = []
    full = {}
    for frac in sorted(fracs, reverse=True):
        aps, trees = {}, []
        for f, model in res["models"].items():
            va = res["va"][f]
            y = data.y[va]
            aps[f] = float(average_precision_score(y, _predict_k(model, data.X(va), frac)))
            trees.append(sum(max(1, int(round(frac * (m.best_iteration_ or 0))))
                             for m in _members(model)))
        if frac == 1.0:
            full = aps
        d = [aps[f] - full[f] for f in aps]
        rows.append({"tree_fraction": frac, "mean_trees": float(np.mean(trees)),
                     "mean_AP": float(np.mean(list(aps.values()))),
                     "delta_vs_full": float(np.mean(d)), "worst_fold_delta": float(np.min(d)),
                     "fold_AP": aps})
    df = pd.DataFrame(rows).sort_values("tree_fraction").reset_index(drop=True)
    df["pct_of_full_AP"] = 100 * df["mean_AP"] / df.loc[df.tree_fraction == 1.0, "mean_AP"].iloc[0]
    return df


def artifact_cost(model, X: pd.DataFrame, fracs=(0.1, 0.25, 0.5, 0.75, 1.0),
                  n_rows: int = 20000, repeats: int = 5, segments: int = 309042) -> pd.DataFrame:
    """Size on disk and single-pass latency of the full-dev artifact at each truncation."""
    Xs = X.iloc[:min(n_rows, len(X))]
    rows = []
    for frac in fracs:
        size = 0
        n_trees = 0
        with tempfile.TemporaryDirectory() as d:
            for i, m in enumerate(_members(model)):
                k = max(1, int(round(frac * (m.best_iteration_ or m.booster_.current_iteration()))))
                p = Path(d) / f"m{i}.txt"
                m.booster_.save_model(str(p), num_iteration=k)
                size += p.stat().st_size
                n_trees += k
        _predict_k(model, Xs.iloc[:100], frac)
        t = []
        for _ in range(repeats):
            t0 = time.perf_counter()
            _predict_k(model, Xs, frac)
            t.append(time.perf_counter() - t0)
        per_row = float(np.median(t)) / len(Xs)
        rows.append({"tree_fraction": frac, "n_trees": n_trees, "model_kb": round(size / 1024, 1),
                     "per_row_us": round(per_row * 1e6, 3),
                     "full_corridor_sec": round(per_row * segments, 3)})
    return pd.DataFrame(rows)


def threads_batch_grid(model, X_corridor: pd.DataFrame, threads=(1, 2, 4, 8),
                       batches=(1_000, 10_000, 100_000, 309_042), repeats: int = 3) -> pd.DataFrame:
    """Wall time for one full corridor pass, chunked at `batch` rows."""
    n = len(X_corridor)
    rows = []
    _predict_k(model, X_corridor.iloc[:1000], 1.0)
    for t in threads:
        for b in batches:
            times = []
            for _ in range(repeats):
                t0 = time.perf_counter()
                for i in range(0, n, b):
                    _predict_k(model, X_corridor.iloc[i:i + b], 1.0, num_threads=t)
                times.append(time.perf_counter() - t0)
            rows.append({"threads": t, "batch_rows": b, "corridor_sec": float(np.median(times)),
                         "rows_per_sec": int(n / np.median(times))})
    return pd.DataFrame(rows)


def peak_predict_mb(model, X: pd.DataFrame) -> float:
    import tracemalloc
    tracemalloc.start()
    tracemalloc.reset_peak()
    model.predict(X)
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    return round(peak / 1024 ** 2, 2)
