#!/usr/bin/env python
"""Run the whole Stage 2 pipeline: labels -> panel -> splits -> QA.

    python scripts/run_stage2.py [conf/config.yaml]

Each step writes a versioned artifact under data/processed/ and a manifest under
data/processed/manifests/. Safe to re-run (idempotent given identical inputs).
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.features import build_panel
from sih_ml.labels import build_labels, qa
from sih_ml.splits import make_splits
from sih_ml.utils.common import get_logger

log = get_logger("stage2")


def main() -> None:
    cfg = sys.argv[1] if len(sys.argv) > 1 else None
    steps = [
        ("labels", lambda: build_labels.main(cfg)),
        ("panel", lambda: build_panel.main(cfg)),
        ("splits", lambda: make_splits.main(cfg)),
        ("qa", lambda: qa.run(cfg)),
    ]
    for name, fn in steps:
        t0 = time.time()
        log.info("=== %s ===", name)
        fn()
        log.info("=== %s done in %.1fs ===", name, time.time() - t0)


if __name__ == "__main__":
    main()
