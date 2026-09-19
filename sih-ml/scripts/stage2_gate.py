#!/usr/bin/env python
"""Evaluate the Stage 2 exit gate and write reports/STAGE2_GATE.md.

Gate criteria (from the Stage 2 plan). PASS = safe to start modelling.
"""
import subprocess
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from sih_ml.utils.common import load_config, resolve  # noqa: E402

MIN_POSITIVE_CLUSTERS = 20


def main() -> int:
    cfg = load_config()
    proc = resolve(cfg, cfg.paths.processed)
    labels = pd.read_parquet(proc / "labels_v1.parquet")
    panel = pd.read_parquet(proc / "panel_v1.parquet")
    folds = pd.read_parquet(proc / "folds_v1.parquet")
    pos = panel.merge(folds, on=["segment_id", "date"]).query("target == 1")

    pytest_rc = subprocess.run(
        [sys.executable, "-m", "pytest", "tests/", "-q"],
        cwd=ROOT, env={**__import__("os").environ, "PYTHONPATH": str(ROOT / "src")},
        capture_output=True, text=True,
    )
    tests_pass = pytest_rc.returncode == 0

    n_clusters = int(pos.event_cluster_id.nunique())
    checks = {
        "leakage/schema/split tests green": tests_pass,
        f"positive clusters >= {MIN_POSITIVE_CLUSTERS}": n_clusters >= MIN_POSITIVE_CLUSTERS,
        "neg:pos ratio in [8, 12]": 8 <= (labels.target == 0).sum() / (labels.target == 1).sum() <= 12,
        "every panel row has a spatial fold": panel.merge(folds, on=["segment_id", "date"]).spatial_fold.notna().all(),
        "every spatial fold has >=1 positive val row":
            all((pos.spatial_fold == f).sum() > 0 for f in range(cfg.split.n_spatial_folds)),
        "each block in exactly one fold": (folds.groupby("spatial_block_id").spatial_fold.nunique() == 1).all(),
        "gold rows are all in final_test":
            bool(panel.merge(folds, on=["segment_id", "date"]).query("label_tier=='gold'").final_test.all()),
        "soil nodata -> NaN": bool(panel.loc[panel.soil_is_missing == 1, "soil_clay_0_5cm_pct"].isna().all()),
        "no duplicate segment-days in panel": not panel.duplicated(["segment_id", "date"]).any(),
        "sources.lock.json present": (proc / "manifests" / "sources.lock.json").exists(),
        "all manifests written": all((proc / "manifests" / f"{n}.json").exists()
                                     for n in ("labels_v1", "panel_v1", "folds_v1")),
    }

    passed = all(checks.values())
    lines = ["# Stage 2 exit gate", "",
             f"## {'✅ PASS — cleared to start Stage 3 modelling' if passed else '❌ NOT PASSED'}",
             "", "| check | result |", "|---|---|"]
    for k, v in checks.items():
        lines.append(f"| {k} | {'✅' if v else '❌'} |")
    lines += ["", "## Context",
              f"- positive segment-days: {int((panel.target==1).sum())}",
              f"- positive clusters (LOECO groups): {n_clusters}",
              f"- distinct positive segments: {int(panel.query('target==1').segment_id.nunique())}",
              f"- verified (gold) rows: {int((panel.label_tier=='gold').sum())}",
              f"- spatial blocks / with positives: {folds.spatial_block_id.nunique()} / {pos.spatial_block_id.nunique()}",
              f"- final_test rows / positives: {int(folds.final_test.sum())} / {int(pos.final_test.sum())}",
              "",
              "Primary metric for Stage 3: **precision@k / average precision under "
              "spatial-block CV and LOECO**, with the out-of-time split reported "
              "separately as the pessimistic bound. See DATA_DECISIONS.md."]
    if not tests_pass:
        lines += ["", "## pytest output", "```", pytest_rc.stdout[-3000:], "```"]
    (resolve(cfg, cfg.paths.reports) / "STAGE2_GATE.md").write_text("\n".join(lines))
    print("\n".join(lines))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
