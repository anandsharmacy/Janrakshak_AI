"""Daily corridor scoring job — the production inference path.

    python -m sih_ml.serve.batch --date 2025-08-15
    python -m sih_ml.serve.batch --backfill 2025-07-01 2025-07-31

One run = one date: validate that the rainfall window is complete -> assemble the
309,042 x 45 matrix -> predict -> calibrate -> rank -> tier -> write
`deploy/scores/date=YYYY-MM-DD/scores.parquet` + `run.json`.

Properties that matter operationally:
  * refuses a date whose rainfall window is incomplete (exit code 3), rather than
    scoring it on a truncated window — the Stage 10 D1 failure mode;
  * idempotent: a date already scored by the same bundle is skipped unless --force;
  * atomic: output is written to a temp dir and renamed, so readers (the API) never
    see a half-written day;
  * self-describing: run.json records the bundle version + manifest hash, the
    feature-store hash, per-stage timings, tier counts, data-quality counts and
    rainfall drift, so any score can be traced to exactly what produced it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.serve.bundle import Bundle
from sih_ml.serve.featurestore import FeatureStore
from sih_ml.serve.monitor import drift_report
from sih_ml.serve.predictor import Predictor, percentile_rank
from sih_ml.serve.validate import InputError, check_date_scorable, check_output, parse_date
from sih_ml.utils.common import REPO_ROOT

log = logging.getLogger("sih.batch")


def bundle_hash(b: Bundle) -> str:
    return hashlib.sha256(json.dumps(b.manifest["files"], sort_keys=True).encode()).hexdigest()[:16]


def run_daily(date, bundle: Bundle, store: FeatureStore, out_root: Path,
              predictor: Predictor | None = None, force: bool = False) -> dict:
    date = parse_date(date)
    sch = bundle.schema
    check_date_scorable(date, store.rain_start, store.rain_end,
                        int(sch["horizon_days"]), int(sch["history_days"]))
    out_root = Path(out_root)
    final = out_root / f"date={date.date()}"
    bh = bundle_hash(bundle)
    if (final / "run.json").exists() and not force:
        prev = json.loads((final / "run.json").read_text())
        if prev.get("bundle_hash") == bh:
            return {**prev, "skipped": "already scored by this bundle"}

    predictor = predictor or Predictor(bundle)
    t = {}
    t0 = time.perf_counter()
    X = store.matrix(date)
    t["features_s"] = time.perf_counter() - t0

    t1 = time.perf_counter()
    raw = predictor.raw(X)
    t["predict_s"] = time.perf_counter() - t1

    t2 = time.perf_counter()
    prob = bundle.calibration(raw, store.slope)
    check_output(prob, raw)
    tier, steep = predictor.tiers(prob, store.slope)
    pct = percentile_rank(raw)
    t["postprocess_s"] = time.perf_counter() - t2

    t3 = time.perf_counter()
    df = pd.DataFrame({"segment_id": store.segment_ids, "raw_score": raw,
                       "p_calibrated": prob, "risk_percentile": pct,
                       "steep": steep, "tier": tier})
    # rank within tier (1 = riskiest): the review/alert CAPACITY per day is a policy
    # decision (MDoNER); consumers take tier_rank <= N instead of trusting a threshold
    # calibrated on the case-control panel
    df["tier_rank"] = df.groupby("tier")["raw_score"].rank(ascending=False, method="first").astype(int)
    out_root.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=".tmp-", dir=out_root))
    df.to_parquet(tmp / "scores.parquet", index=False)

    cat_idx = [sch["features"].index(c) for c in sch["categorical"]]
    rain_idx = store.rain_idx
    manifest = {
        "date": str(date.date()), "bundle_version": bundle.version, "bundle_hash": bh,
        "featurestore_schema_sha256": store.manifest["schema_sha256"],
        "rain_feed_end": str(store.rain_end.date()),
        "n_segments": int(len(df)),
        "tiers": {k: int(v) for k, v in pd.Series(tier).value_counts().items()},
        "data_quality": {
            "rows_with_any_nan_rainfall": int(np.isnan(X[:, rain_idx]).any(axis=1).sum()),
            "unknown_category_cells": int(np.isnan(X[:, cat_idx]).sum()),
            "non_finite_scores": int((~np.isfinite(raw)).sum())},
        "drift": drift_report(store.rain, date - pd.Timedelta(days=int(sch["horizon_days"])),
                              bundle.reference),
        "score_quantiles": {str(q): float(np.quantile(raw, q)) for q in (0.5, 0.9, 0.99, 0.999)},
    }
    t["write_s"] = time.perf_counter() - t3
    t["total_s"] = time.perf_counter() - t0
    manifest["timings"] = t
    manifest["written_utc"] = pd.Timestamp.now(tz="UTC").isoformat()
    (tmp / "run.json").write_text(json.dumps(manifest, indent=1))
    if final.exists():
        shutil.rmtree(final)
    os.replace(tmp, final)                       # atomic on the same filesystem
    _write_prom(out_root, manifest)
    log.info(json.dumps({"event": "batch_scored", **{k: manifest[k] for k in
                                                     ("date", "bundle_version", "tiers")},
                         "total_s": round(t["total_s"], 3)}))
    return manifest


def _write_prom(out_root: Path, m: dict) -> None:
    """Metrics for node-exporter's textfile collector (the batch is not a server)."""
    lines = [f'sih_batch_last_success_timestamp {pd.Timestamp.now(tz="UTC").timestamp():.0f}',
             f'sih_batch_duration_seconds {m["timings"]["total_s"]:.3f}',
             f'sih_batch_scored_date_timestamp {pd.Timestamp(m["date"]).timestamp():.0f}']
    lines += [f'sih_batch_tier_count{{tier="{k}"}} {v}' for k, v in m["tiers"].items()]
    for k, v in m["drift"].items():
        lines += [f'sih_rain_drift_psi{{feature="{k}"}} {v["psi_30d_vs_month_climatology"]:.4f}',
                  f'sih_rain_drift_warn{{feature="{k}"}} {int(v["warn"])}']
    tmp = out_root / ".batch.prom.tmp"
    tmp.write_text("\n".join(lines) + "\n")
    os.replace(tmp, out_root / "batch.prom")


def _defaults():
    root = Path(os.environ.get("SIH_DEPLOY_ROOT", REPO_ROOT / "deploy"))
    return (Path(os.environ.get("SIH_BUNDLE", root / "bundles" / "current")),
            Path(os.environ.get("SIH_STORE", root / "featurestore")),
            Path(os.environ.get("SIH_SCORES", root / "scores")))


def main(argv=None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stderr)
    b_dir, s_dir, o_dir = _defaults()
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--date")
    g.add_argument("--backfill", nargs=2, metavar=("START", "END"))
    ap.add_argument("--bundle", default=b_dir)
    ap.add_argument("--store", default=s_dir)
    ap.add_argument("--out", default=o_dir)
    ap.add_argument("--threads", type=int, default=0)
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args(argv)

    bundle = Bundle.load(a.bundle)
    store = FeatureStore.load(a.store, bundle.schema)
    pred = Predictor(bundle, a.threads)
    dates = [a.date] if a.date else [str(d.date()) for d in pd.date_range(*a.backfill)]
    rc = 0
    for d in dates:
        try:
            m = run_daily(d, bundle, store, Path(a.out), pred, a.force)
            print(json.dumps({"date": m["date"], "tiers": m["tiers"],
                              "total_s": m.get("timings", {}).get("total_s"),
                              "skipped": m.get("skipped")}))
        except InputError as e:
            log.error(json.dumps({"event": "batch_refused", "date": d, "code": e.code,
                                  "detail": e.detail}))
            rc = 3
    return rc


if __name__ == "__main__":
    sys.exit(main())
