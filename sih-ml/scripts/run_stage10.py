#!/usr/bin/env python
"""Stage 10 — one campaign of the continuous improvement loop.

    python scripts/run_stage10.py [conf/improve_config.yaml]

Reconstructs and verifies the champion, re-diagnoses its error patterns, calibrates
the A/A noise floor, runs the experiment backlog (correctness -> backlog -> greedy
composition), materialises the champion, measures its efficiency frontier, and
appends every decision to reports/stage10/EXPERIMENT_LEDGER.jsonl. Dev data only.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.train.run_improve import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
