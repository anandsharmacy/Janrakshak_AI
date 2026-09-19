#!/usr/bin/env python
"""Stage 8 — final model validation.

    python scripts/run_stage8.py

Selects nothing and changes nothing. Verifies the frozen config hash against
reports/stage7/PREREGISTRATION.json, retrains it to confirm the recorded test number
reproduces, then runs final testing, robustness, generalization and
production-readiness analysis on that frozen artifact.

Reads the locked test split for REPORTING only; the read is appended to
TEST_SET_LEDGER.json as kind="report", kept distinct from the single kind="decision"
opening made at the end of Stage 7.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.train.run_final import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
