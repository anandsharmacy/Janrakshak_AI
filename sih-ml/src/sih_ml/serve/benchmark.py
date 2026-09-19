"""Stage 11 measurements — accuracy of every model-side optimization, and the
end-to-end cost of the inference pipeline. Nothing here is estimated.

    python -m sih_ml.serve.benchmark            # writes reports/stage11/

Part A  accuracy of compression variants, measured exactly like a Stage 10
        simplification: champion fold models under 5 folds x 3 seeds, each variant
        derived from the SAME fold models, paired deltas, A/A-calibrated
        non-inferiority rule, steep-terrain / calibration / monotonicity guardrails.
          trunc_*   tree-count truncation (the GBDT analogue of pruning)
          fp32      thresholds, leaf values AND inputs rounded to float32 — what an
                    ONNX TreeEnsemble / GPU-FIL runtime computes
          fp16      the same at float16 — what "FP16 quantization" means for trees
          distill   a 300-tree student fitted to the teacher's scores (cross-entropy
                    on soft labels), one untuned configuration
Part B  pipeline cost: naive (Stage 2 feature code per segment + pandas + pickled
        calibrators) vs optimized (feature store + numpy + JSON calibration), per
        stage, for one monsoon day over the whole corridor; plus a 30-day backfill.

Runtime/latency/memory of alternative runtimes (ONNX Runtime, Treelite) are measured
by scripts/bench_runtimes.py in the isolated deploy environment.
"""
from __future__ import annotations

import json
import re
import tempfile
import time
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd

from sih_ml.improve import candidate as C
from sih_ml.improve import decide as Dc
from sih_ml.improve import diagnose as Dg
from sih_ml.improve.features import coverage_mask
from sih_ml.improve.ledger import Ledger, spec_hash
from sih_ml.models.dataset import load_data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.utils.common import REPO_ROOT, get_logger, load_config_with_base

log = get_logger("stage11")
RDIR = REPO_ROOT / "reports" / "stage11"
NUM_RE = re.compile(r"^(threshold|leaf_value)=(.*)$")


# --------------------------------------------------------------------------- #
# variants
# --------------------------------------------------------------------------- #
def reduced_precision_booster(booster: lgb.Booster, dtype, num_iteration=None) -> lgb.Booster:
    """Rewrite a LightGBM text model with thresholds and leaf values rounded to `dtype`.
    Categorical thresholds are small integer indices and survive both float32 and
    float16 exactly."""
    out = []
    for line in booster.model_to_string(num_iteration=num_iteration).splitlines():
        if line.startswith("tree_sizes="):
            continue        # byte offsets of each tree; stale once digits change — LightGBM
                            # falls back to sequential parsing without them
        m = NUM_RE.match(line)
        if m:
            vals = np.array(m.group(2).split(), float).astype(dtype).astype(float)
            line = f"{m.group(1)}=" + " ".join(repr(float(v)) for v in vals)
        out.append(line)
    return lgb.Booster(model_str="\n".join(out) + "\n")


class Variant:
    """predict(DataFrame) -> probability, from one fold model."""

    def __init__(self, fn):
        self.fn = fn

    def predict(self, X):
        return self.fn(X)


def _round_inputs(X: pd.DataFrame, dtype, cats) -> pd.DataFrame:
    X = X.copy()
    for c in X.columns:
        if c not in cats:
            X[c] = X[c].to_numpy(float).astype(dtype).astype(float)
    return X


def make_variants(model: LGBMBaseline, cats: list[str], student=None) -> dict[str, Variant]:
    b, bi = model.booster_, model.best_iteration_
    out = {}
    for frac in (0.1, 0.25, 0.5):
        k = max(1, int(round(frac * bi)))
        out[f"trunc_{frac:g}"] = Variant(lambda X, k=k: b.predict(X[model.features], num_iteration=k))
    for name, dt in (("fp32", np.float32), ("fp16", np.float16)):
        rb = reduced_precision_booster(b, dt, bi)
        out[name] = Variant(lambda X, rb=rb, dt=dt: rb.predict(_round_inputs(X[model.features], dt, cats)))
    if student is not None:
        out["distill_300"] = Variant(lambda X, s=student: s.predict(X[model.features]))
    return out


def fit_student(c: C.Candidate, teacher: LGBMBaseline, tr: np.ndarray, seed: int,
                n_trees: int = 300) -> lgb.Booster:
    X = c.data.X(tr)
    soft = teacher.predict(X)
    p = dict(c.cfg.lgbm)
    params = {"objective": "cross_entropy", "learning_rate": 0.1, "num_leaves": p["num_leaves"],
              "max_depth": p["max_depth"], "min_child_samples": p["min_child_samples"],
              "lambda_l1": p["reg_alpha"], "lambda_l2": p["reg_lambda"],
              "feature_fraction": p["colsample_bytree"], "bagging_fraction": p["subsample"],
              "bagging_freq": p["subsample_freq"], "verbosity": -1, "seed": seed,
              "deterministic": True, "force_row_wise": True,
              "monotone_constraints": [1 if f in c.monotone else 0 for f in c.data.features]}
    ds = lgb.Dataset(X, label=soft, categorical_feature=c.data.categorical)
    return lgb.train(params, ds, num_boost_round=n_trees)


# --------------------------------------------------------------------------- #
# Part A
# --------------------------------------------------------------------------- #
def champion_candidate():
    reg = json.loads((REPO_ROOT / "models" / "registry.json").read_text())
    v = next(x for x in reg["versions"] if x["version"] == reg["champion"])
    data, cfg = load_data(REPO_ROOT / "conf" / "improve_config.yaml")
    c = C.build_candidate(v["state"], v["version"], data, cfg,
                          coverage=coverage_mask(data, cfg), pctl=None)
    return c, v, cfg


def aa_noise_for(state: dict) -> dict:
    """The A/A floors Stage 10 measured for this exact champion state."""
    sha = spec_hash(state)
    rows = [r for r in Ledger(REPO_ROOT / "reports/stage10/EXPERIMENT_LEDGER.jsonl").read()
            if r.get("type") == "aa_calibration" and r.get("state_sha16") == sha]
    if not rows:
        raise RuntimeError("no A/A calibration recorded for the champion — run make stage10")
    r = rows[-1]
    return {k: r[k] for k in ("delta_floor", "worst_fold_floor", "steep_roc_floor",
                              "cal_ratio_floor")} | {"campaign_id": r["campaign_id"]}


def accuracy_part(folds=(0, 1, 2, 3, 4), seeds=(42, 1337, 2024)) -> dict:
    c, v, cfg = champion_candidate()
    ic = load_config_with_base(REPO_ROOT / "conf" / "improve_config.yaml").improve
    noise = aa_noise_for(v["state"])
    n = len(c.data.panel)
    fold_of = np.full(n, -1)
    res = {"original": {"ap": {s: {} for s in seeds}, "oof": {s: np.full(n, np.nan) for s in seeds}}}
    kept = {}
    t0 = time.time()
    for s in seeds:
        for f in folds:
            model, va, pred, tr = C.fit_fold(c, f, s)
            fold_of[va] = f
            y = c.data.y[va]
            res["original"]["ap"][s][f] = C._ap(y, pred)
            res["original"]["oof"][s][va] = pred
            student = fit_student(c, model, tr, s + f)
            Xva = c.data.X(va)
            for name, var in make_variants(model, c.data.categorical, student).items():
                r = res.setdefault(name, {"ap": {x: {} for x in seeds},
                                          "oof": {x: np.full(n, np.nan) for x in seeds}})
                p = var.predict(Xva)
                r["ap"][s][f] = C._ap(y, p)
                r["oof"][s][va] = p
                if s == seeds[0] and f == folds[0]:
                    kept[name] = (var, va)
            if s == seeds[0] and f == folds[0]:
                kept["original"] = (model, va)
        log.info("  seed %d done (%.0fs)", s, time.time() - t0)
    for r in res.values():
        r["fold_of"] = fold_of

    lim = dict(ic.guardrails)
    bins = list(ic.calibration_bins)

    def guard(name):
        r = res[name]
        cal = Dg.terrain_cal_per_seed(c, r, list(folds), bins)
        model, va = kept[name]
        return {"steep_roc": C.steep_roc(c, r, float(lim["steep_slope_deg"]))["steep_roc"],
                "worst_terrain_cal_ratio": float(np.mean(list(cal.values()))),
                "monotonicity_violations": C.monotonicity(c, model, va, seed=42),
                "corridor_sec": 0.0, "model_mb": 0.0}      # cost measured in bench_runtimes

    g0 = guard("original")
    rows = []
    for name in [k for k in res if k != "original"]:
        D = Dc.delta_table(res[name]["ap"], res["original"]["ap"], list(seeds), list(seeds), list(folds))
        cmp = Dc.compare(D, list(folds), int(ic.min_folds_improved), float(ic.alpha))
        g = guard(name)
        fails = Dc.guardrail_failures(g, g0, cmp, noise, lim)
        dec, why = Dc.decide("simplification", cmp, fails, noise, float(ic.ni_margin_cap))
        rows.append({"variant": name, "mean_AP": float(np.nanmean([res[name]["ap"][s][f]
                                                                  for s in seeds for f in folds])),
                     "delta_AP": cmp["mean_delta"], "worst_fold_delta": cmp["worst_fold_delta"],
                     "folds_worse": int(sum(d < 0 for d in cmp["fold_avg_deltas"])),
                     "seeds_negative": int(sum(r["mean_delta"] < 0 for r in cmp["per_seed"])),
                     "steep_roc_delta": g["steep_roc"] - g0["steep_roc"],
                     "cal_ratio": g["worst_terrain_cal_ratio"],
                     "monotonicity_violations": g["monotonicity_violations"],
                     "non_inferior": dec == Dc.ACCEPT, "decision": dec, "reason": why})
        log.info("  %-12s dAP %+.4f  worst fold %+.4f  steep %+.4f  cal %.2fx  -> %s",
                 name, cmp["mean_delta"], cmp["worst_fold_delta"],
                 g["steep_roc"] - g0["steep_roc"], g["worst_terrain_cal_ratio"], dec)
    base_ap = float(np.nanmean([res["original"]["ap"][s][f] for s in seeds for f in folds]))
    return {"champion": v["version"], "noise": noise, "original_mean_AP": base_ap,
            "original_guard": g0, "variants": rows}


# --------------------------------------------------------------------------- #
# Part B
# --------------------------------------------------------------------------- #
def pipeline_part(date: str = "2025-08-15", backfill_days: int = 30) -> dict:
    """Naive vs optimized daily scoring of the full corridor, stage by stage."""
    from sih_ml.features.rainfall import build_cell_series, rainfall_features
    from sih_ml.models.calibration import Calibrator
    from sih_ml.optimize.calibrate import slope_stratum
    from sih_ml.serve.batch import run_daily
    from sih_ml.serve.bundle import Bundle
    from sih_ml.serve.featurestore import FeatureStore, static_table
    from sih_ml.serve.predictor import Predictor
    from sih_ml.utils.common import load_config, resolve

    d = pd.Timestamp(date)
    b = Bundle.load(REPO_ROOT / "deploy/bundles/current")
    out = {"date": date}

    # ---- naive: what "just reuse the training code" looks like at corridor scale
    t = {}
    t0 = time.perf_counter()
    pc = load_config()
    series, cells = build_cell_series(resolve(pc, pc.paths.chirps_csv))
    static = static_table(pc)
    t["load_sources_s"] = time.perf_counter() - t0
    t1 = time.perf_counter()
    pairs = pd.DataFrame({"segment_id": static.segment_id, "date": d})
    rain = rainfall_features(pairs, series, static[["segment_id", "cell_id"]], 1)
    t["rainfall_features_s"] = time.perf_counter() - t1
    t2 = time.perf_counter()
    df = static.merge(rain.drop(columns=["cell_id", "date"]), on="segment_id")
    df["month"] = d.month
    df["doy_sin"] = np.sin(2 * np.pi * d.dayofyear / 365.25)
    df["doy_cos"] = np.cos(2 * np.pi * d.dayofyear / 365.25)
    df["is_monsoon"] = int(d.month in (6, 7, 8, 9))
    for cc in b.schema["categorical"]:
        df[cc] = df[cc].astype("string").fillna("__missing__").astype("category")
    for cc in b.features:
        if cc not in b.schema["categorical"]:
            df[cc] = pd.to_numeric(df[cc], errors="coerce")
    t["assemble_frame_s"] = time.perf_counter() - t2
    t3 = time.perf_counter()
    mdir = Path(b.manifest["source_model"])
    m = LGBMBaseline.load(mdir / "model.txt")
    raw_naive = m.predict(df[m.features])
    t["predict_s"] = time.perf_counter() - t3
    t4 = time.perf_counter()
    s = np.clip(np.digitize(np.nan_to_num(df.slope_mean_deg.to_numpy(float)), b.calibration.bins[1:-1]),
                0, len(b.calibration.bins) - 2)
    p_naive = Calibrator.load(mdir / "calibrator_pooled.pkl").transform(raw_naive)
    for k in range(len(b.calibration.bins) - 1):
        f = mdir / f"calibrator_slope_{k}.pkl"
        if f.exists():
            p_naive[s == k] = Calibrator.load(f).transform(raw_naive[s == k])
    t["calibrate_s"] = time.perf_counter() - t4
    t["total_s"] = time.perf_counter() - t0
    out["naive"] = t

    # ---- optimized: the production path
    tl = time.perf_counter()
    store = FeatureStore.load(REPO_ROOT / "deploy/featurestore", b.schema)
    pred = Predictor(b, 0)
    out["optimized_cold_start_s"] = time.perf_counter() - tl
    with tempfile.TemporaryDirectory() as tmp:
        man = run_daily(date, b, store, Path(tmp), pred, force=True)
        out["optimized"] = man["timings"]
        opt = pd.read_parquet(Path(tmp) / f"date={date}" / "scores.parquet")
        order = pd.Index(opt.segment_id).get_indexer(df.segment_id)
        out["naive_vs_optimized"] = {
            "max_abs_raw_diff": float(np.max(np.abs(opt.raw_score.to_numpy()[order] - raw_naive))),
            "max_abs_prob_diff": float(np.max(np.abs(opt.p_calibrated.to_numpy()[order] - p_naive)))}
        # a month of backfill through the same path
        days = pd.date_range(end=d, periods=backfill_days)
        tb = time.perf_counter()
        for day in days:
            run_daily(str(day.date()), b, store, Path(tmp), pred, force=True)
        out["backfill"] = {"days": backfill_days, "total_s": time.perf_counter() - tb,
                           "per_day_s": (time.perf_counter() - tb) / backfill_days}
    return out


def main() -> None:
    RDIR.mkdir(parents=True, exist_ok=True)
    log.info("=== Part B: pipeline cost ===")
    B = pipeline_part()
    log.info("  naive %.2fs vs optimized %.2fs | parity raw %.2e prob %.2e",
             B["naive"]["total_s"], B["optimized"]["total_s"],
             B["naive_vs_optimized"]["max_abs_raw_diff"], B["naive_vs_optimized"]["max_abs_prob_diff"])
    (RDIR / "benchmark_pipeline.json").write_text(json.dumps(B, indent=1, default=str))
    log.info("=== Part A: accuracy of compression variants (5 folds x 3 seeds) ===")
    A = accuracy_part()
    pd.DataFrame(A["variants"]).to_csv(RDIR / "accuracy_variants.csv", index=False)
    (RDIR / "benchmark_accuracy_pipeline.json").write_text(json.dumps({"accuracy": A, "pipeline": B},
                                                                      indent=1, default=str))
    log.info("done -> %s", RDIR)


if __name__ == "__main__":
    main()
