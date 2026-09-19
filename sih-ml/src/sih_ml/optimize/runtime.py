"""Stage 7 §6 — the non-accuracy half of the scorecard: latency, memory, model size.

The brief asks for these alongside accuracy, and for this product they are not a
formality: the corridor has ~309k road segments that must be scored every day, and
the output feeds a routing layer that a user waits on. A configuration that wins on
AP by a hair and costs 10x the inference budget is the wrong choice, which is
exactly the trade Stage 6 made when it picked a 4-leaf model at statistical parity.

Measured, not estimated:
  * model size  — the serialised booster on disk, plus trees and total leaf count
  * latency     — repeated timed predictions, reported as median and p95, then
                  extrapolated to a full daily corridor scoring pass
  * memory      — peak Python allocation during a prediction, via tracemalloc

Caveat recorded honestly: this is a single-machine, single-thread-pool measurement
on the dev box. It is valid for COMPARING configurations (the point of the table)
and should be re-measured on the deployment target before any latency SLA is
promised.
"""
from __future__ import annotations

import tempfile
import time
import tracemalloc
from pathlib import Path

import numpy as np

from sih_ml.models.lgbm_baseline import LGBMBaseline


def model_size(model: LGBMBaseline) -> dict:
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "m.txt"
        model.booster_.save_model(str(p), num_iteration=model.best_iteration_)
        size_bytes = p.stat().st_size
    dump = model.booster_.dump_model(num_iteration=model.best_iteration_)
    trees = dump.get("tree_info", [])
    leaves = sum(t.get("num_leaves", 0) for t in trees)
    return {
        "model_bytes": int(size_bytes),
        "model_kb": round(size_bytes / 1024, 1),
        "n_trees": len(trees),
        "total_leaves": int(leaves),
        "mean_leaves_per_tree": round(leaves / max(1, len(trees)), 2),
    }


def latency(model: LGBMBaseline, X, n_rows: int = 20000, repeats: int = 5,
            deployment_segments: int = 309042) -> dict:
    """Timed predictions on a fixed slice, plus the daily-pass extrapolation."""
    Xs = X.iloc[:min(n_rows, len(X))]
    model.predict(Xs.iloc[:100])                       # warm up
    times = []
    for _ in range(repeats):
        t0 = time.perf_counter()
        model.predict(Xs)
        times.append(time.perf_counter() - t0)
    times = np.array(times)
    per_row_us = float(np.median(times) / len(Xs) * 1e6)
    return {
        "n_rows": int(len(Xs)), "repeats": int(repeats),
        "median_sec": float(np.median(times)),
        "p95_sec": float(np.percentile(times, 95)),
        "per_row_us": round(per_row_us, 3),
        "rows_per_sec": int(len(Xs) / np.median(times)),
        "full_corridor_sec": round(per_row_us * deployment_segments / 1e6, 2),
        "deployment_segments": int(deployment_segments),
    }


def peak_memory(model: LGBMBaseline, X, n_rows: int = 20000) -> dict:
    Xs = X.iloc[:min(n_rows, len(X))]
    tracemalloc.start()
    tracemalloc.reset_peak()
    model.predict(Xs)
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    return {"predict_peak_mb": round(peak / 1024 ** 2, 2), "n_rows": int(len(Xs))}


def profile(model: LGBMBaseline, X, cfg_runtime) -> dict:
    n = int(cfg_runtime.get("n_latency_rows", 20000))
    return {
        **model_size(model),
        **latency(model, X, n, int(cfg_runtime.get("repeats", 5)),
                  int(cfg_runtime.get("deployment_segments", 309042))),
        **peak_memory(model, X, n),
    }
