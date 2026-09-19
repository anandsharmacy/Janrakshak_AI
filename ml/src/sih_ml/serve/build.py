"""Build the deployment artifacts from the registry champion.

    python -m sih_ml.serve.build                   # bundle + feature store
    python -m sih_ml.serve.build --version final_v3 --num-iteration 300   # a variant

Writes deploy/bundles/<version>/, points deploy/bundles/current at it, and builds
deploy/featurestore/. Build-time only: needs scikit-learn (to read the Stage 10
calibrator pickles once); the runtime does not.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from sih_ml.serve.bundle import Bundle, build_bundle
from sih_ml.serve.featurestore import FeatureStore, default_store_dir, feature_groups
from sih_ml.serve.monitor import rainfall_reference
from sih_ml.utils.common import REPO_ROOT

CAVEAT = ("p_calibrated is calibrated on a case-control training panel (~10 sampled "
          "negatives per positive), so its absolute level overstates the true daily "
          "probability on the full corridor; Stage 9 also measured calibration NOT "
          "transferring to a new region (worst terrain stratum 2.65x). Rank by "
          "risk_percentile. Do not feed p_calibrated into the routing penalty on unseen "
          "terrain without recalibrating on local history.")


def policy_from_card(card: dict) -> dict:
    return {"alert_probability_threshold": float(card["dev_operating_threshold_fn_fp_10"]),
            "threshold_origin": "dev out-of-fold, cost-optimal at FN:FP = 10 (Stage 7 "
                                "measured 10 dominating the unvalidated 20); ratio still "
                                "to be settled with MDoNER",
            "steep_slope_deg": 10.0,
            "steep_rule": "steep segments above threshold -> human_review, never autonomous "
                          "alerting (REMEDIATION.md §D)",
            "primary_output": "risk_percentile",
            "probability_caveat": CAVEAT}


def main(argv=None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default=None, help="registry version (default: champion)")
    ap.add_argument("--num-iteration", type=int, default=None)
    ap.add_argument("--out", default=str(REPO_ROOT / "deploy" / "bundles"))
    ap.add_argument("--skip-store", action="store_true")
    a = ap.parse_args(argv)

    reg = json.loads((REPO_ROOT / "models" / "registry.json").read_text())
    version = a.version or reg["champion"]
    model_dir = REPO_ROOT / "models" / version
    card = json.loads((model_dir / "model_card.json").read_text())
    feats = json.loads((model_dir / "model.meta.json").read_text())["features"]

    from sih_ml.features.rainfall import build_cell_series
    from sih_ml.utils.common import load_config, load_config_with_base, resolve
    pc = load_config()
    series, _ = build_cell_series(resolve(pc, pc.paths.chirps_csv))
    reference = rainfall_reference(series)
    # the bins the Stage 10 calibrators were fitted on (calibrator_slope_<k> = bin k)
    bins = list(load_config_with_base(REPO_ROOT / "conf" / "improve_config.yaml")
                .improve.calibration_bins)

    name = version if a.num_iteration is None else f"{version}-t{a.num_iteration}"
    out = build_bundle(model_dir, Path(a.out) / name, policy=policy_from_card(card),
                       reference=reference, feature_groups=feature_groups(feats),
                       calibration_bins=bins,
                       num_iteration=a.num_iteration,
                       extra_manifest={"registry_champion": reg["champion"]})
    b = Bundle.load(out)
    print(json.dumps({"bundle": str(out), "version": b.version, "n_trees": b.manifest["n_trees"]}))
    if a.num_iteration is None:
        cur = Path(a.out) / "current"
        if cur.is_symlink() or cur.exists():
            cur.unlink()
        os.symlink(name, cur)

    if not a.skip_store:
        store = FeatureStore.build(b.schema, pc)
        d = store.save(default_store_dir())
        print(json.dumps({"featurestore": str(d), "segments": store.manifest["n_segments"],
                          "cells": store.manifest["n_cells"],
                          "rain": [store.manifest["rain_first"], store.manifest["rain_last"]]}))


if __name__ == "__main__":
    main()
