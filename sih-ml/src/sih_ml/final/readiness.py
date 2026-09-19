"""Stage 8 §5 — production readiness.

Two things this module deliberately does NOT do:

* **It does not recommend quantization, pruning, ONNX or TensorRT by default.** Those
  are answers to a latency or memory problem. This model is a ~700 KB LightGBM
  ensemble that scores the entire 309k-segment corridor in about a second on one
  core, against a once-daily batch cadence — roughly four orders of magnitude of
  headroom. Converting it would add a toolchain, a numerical-equivalence risk and a
  second artifact to version, in exchange for nothing measurable. `optimization_advice`
  states the thresholds at which each would become worth doing, so the recommendation
  is falsifiable rather than a matter of taste.

* **It does not declare the model production-ready.** It evaluates gates. Whether the
  remaining failures are acceptable is a decision for the people who own the
  consequences of a missed road closure, and the gates are written so that decision
  is made with the weaknesses in view.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.models.dataset import Data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.utils.common import get_logger

log = get_logger("stage8.ready")


def scalability(model: LGBMBaseline, X, sizes=(1000, 10000, 50000, 100000),
                repeats: int = 3, segments: int = 309042) -> pd.DataFrame:
    """Measure throughput at several batch sizes to confirm it scales linearly and
    to size the real daily job rather than extrapolating from one point."""
    rows = []
    model.predict(X.iloc[:100])                                   # warm up
    for n in sizes:
        if n > len(X):
            continue
        Xs = X.iloc[:n]
        ts = []
        for _ in range(repeats):
            t0 = time.perf_counter()
            model.predict(Xs)
            ts.append(time.perf_counter() - t0)
        med = float(np.median(ts))
        rows.append({"n_rows": n, "median_sec": med,
                     "per_row_us": round(med / n * 1e6, 3),
                     "rows_per_sec": int(n / med),
                     "projected_corridor_sec": round(med / n * segments, 3)})
    return pd.DataFrame(rows)


def reproducibility_check(data: Data, cfg, prereg: dict, seed: int,
                          reference_ap: float, te_idx, observed_ap: float) -> dict:
    """Did retraining the frozen config reproduce the recorded test number exactly?

    This is the strongest available evidence that (a) the pipeline is deterministic
    and (b) the artifact being analysed in Stage 8 is byte-for-byte the artifact that
    produced the pre-registered result — i.e. nothing drifted between the opening and
    this report.
    """
    delta = abs(observed_ap - reference_ap)
    return {
        "ledger_average_precision": float(reference_ap),
        "recomputed_average_precision": float(observed_ap),
        "abs_difference": float(delta),
        "bit_identical": bool(delta < 1e-12),
        "config_sha256_16": prereg["config_sha256_16"],
        "seed": int(seed),
        "determinism_settings": {
            "lightgbm_deterministic": True, "force_row_wise": True,
            "numpy_seed": int(seed), "fold_order": "fixed (parquet, no shuffle on load)",
        },
        "caveat": ("Bit-exactness holds for this machine and these pinned library "
                   "versions. LightGBM/OpenMP version changes or a different CPU "
                   "architecture can alter floating-point summation order; pin "
                   "requirements.txt for cross-machine reproduction."),
    }


def deployment_gates(metrics: dict, robustness: dict, runtime: dict) -> pd.DataFrame:
    """Pre-stated minimum thresholds, each with the reason it exists.

    These are proposed engineering gates, not thresholds negotiated with MDoNER —
    that conversation has not happened, and the one cost parameter inherited from it
    (FN:FP = 20) is still an unvalidated placeholder.
    """
    steep_lift = metrics.get("steep_AP", np.nan) / max(metrics.get("steep_base_rate", np.nan), 1e-9)
    gates = [
        {"gate": "beats chance on held-out ground",
         "threshold": "test AP / base rate > 2.0",
         "measured": f"{metrics['average_precision'] / metrics['base_rate']:.2f}x",
         "pass": metrics["average_precision"] / metrics["base_rate"] > 2.0,
         "why": "below this the ranking is not worth the pipeline"},
        {"gate": "top-of-ranking precision",
         "threshold": "precision@100 >= 0.50",
         "measured": f"{metrics.get('precision@100', np.nan):.3f}",
         "pass": metrics.get("precision@100", 0) >= 0.50,
         "why": "operators act on the top of the list, not the whole list"},
        {"gate": "recall at the operating threshold",
         "threshold": ">= 0.80",
         "measured": f"{metrics.get('recall', np.nan):.3f}",
         "pass": metrics.get("recall", 0) >= 0.80,
         "why": "a missed closure is the costly error for this product"},
        {"gate": "STEEP-TERRAIN discrimination",
         "threshold": "steep ROC-AUC >= 0.70",
         "measured": f"{metrics.get('steep_roc_auc', np.nan):.3f}",
         "pass": metrics.get("steep_roc_auc", 0) >= 0.70,
         "why": ("the roads that actually close are all steep; global AP is inflated "
                 "by plains-vs-hills, which routing already knows")},
        {"gate": "steep-terrain lift",
         "threshold": ">= 2.0x",
         "measured": f"{steep_lift:.2f}x",
         "pass": bool(steep_lift >= 2.0),
         "why": "operational value, not global value"},
        {"gate": "probability calibration transfers",
         "threshold": "worst terrain stratum within 1.5x on unseen region",
         "measured": f"{robustness.get('worst_test_stratum_ratio', np.nan):.2f}x",
         "pass": bool(robustness.get("worst_test_stratum_ratio", 99) <= 1.5),
         "why": "calibrated P becomes the routing penalty W = dist*(1 + lambda*P)"},
        {"gate": "survives rainfall forecast error",
         "threshold": ">= 80% of clean AP at sigma = 0.25",
         "measured": f"{robustness.get('pct_at_sigma_025', np.nan):.1f}%",
         "pass": bool(robustness.get("pct_at_sigma_025", 0) >= 80.0),
         "why": "deployment feeds a forecast, not an observation"},
        {"gate": "rainfall is actually driving the prediction",
         "threshold": "positives lose >= 30% of score under zero rainfall",
         "measured": f"{100 * (1 - robustness.get('retained_frac', np.nan)):.1f}%",
         "pass": bool((1 - robustness.get("retained_frac", 1.0)) >= 0.30),
         "why": "otherwise it is a terrain map with a weather-shaped label"},
        {"gate": "daily corridor scoring fits the batch window",
         "threshold": "< 300 s for 309,042 segments",
         "measured": f"{runtime.get('full_corridor_sec', np.nan):.2f} s",
         "pass": runtime.get("full_corridor_sec", 1e9) < 300,
         "why": "once-daily batch job"},
        {"gate": "artifact size is deployable",
         "threshold": "< 50 MB",
         "measured": f"{runtime.get('model_kb', np.nan) / 1024:.2f} MB",
         "pass": runtime.get("model_kb", 1e9) / 1024 < 50,
         "why": "ships inside a container image"},
        {"gate": "reproducible from config + seed",
         "threshold": "retrain reproduces the recorded test AP",
         "measured": ("bit-identical" if robustness.get("bit_identical")
                      else "DIFFERS"),
         "pass": bool(robustness.get("bit_identical", False)),
         "why": "an unreproducible model cannot be audited or rolled back"},
    ]
    return pd.DataFrame(gates)


def optimization_advice(runtime: dict, segments: int = 309042) -> list[dict]:
    """When each inference optimization would become worth doing. Measured against
    the actual budget so the 'no' is falsifiable."""
    sec = runtime.get("full_corridor_sec", np.nan)
    mb = runtime.get("model_kb", np.nan) / 1024
    return [
        {"technique": "quantization (int8 leaf values)",
         "recommended": False,
         "reason": (f"model is {mb:.2f} MB and the full corridor scores in {sec:.2f} s. "
                    "LightGBM inference is memory-bandwidth-bound on tree traversal, not "
                    "arithmetic-bound, so quantizing leaves saves neither meaningfully."),
         "revisit_if": "artifact must fit under ~1 MB (edge/embedded deployment)"},
        {"technique": "pruning / tree-count reduction",
         "recommended": False,
         "reason": ("early stopping already selected the round count on an "
                    "event-grouped holdout; cutting further trades measured accuracy "
                    "for latency the product does not need."),
         "revisit_if": "per-request latency ever becomes user-facing (< 50 ms budget)"},
        {"technique": "ONNX / Treelite / TensorRT export",
         "recommended": False,
         "reason": ("adds a second artifact, a conversion step and a numerical-"
                    "equivalence risk to version and test, for a job with ~300x "
                    "headroom in its batch window."),
         "revisit_if": ("the serving language stops being Python, or per-row latency "
                        "must drop below ~1 us")},
        {"technique": "GPU inference",
         "recommended": False,
         "reason": f"{sec:.2f} s on one CPU core for the entire corridor.",
         "revisit_if": "corridor grows >100x or cadence becomes sub-minute"},
        {"technique": "batch the daily scoring job + cache static features",
         "recommended": True,
         "reason": ("static terrain/soil/road columns never change; only the rainfall "
                    "block needs recomputing daily. This is where the real pipeline "
                    "cost sits — feature assembly, not model inference."),
         "revisit_if": "n/a — do this"},
    ]
