#!/usr/bin/env python
"""Stage 6 — fine-tuning + hyperparameter optimization.

    python scripts/run_stage6.py                  # run (resumes an existing study)
    python scripts/run_stage6.py conf/other.yaml

The Optuna study persists to studies/*.db, so re-running continues from the trials
already completed. Delete that file to start a fresh search.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.train.run_hpo import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
