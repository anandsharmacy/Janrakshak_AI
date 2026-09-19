#!/usr/bin/env python
"""OPEN THE LOCKED TEST SET. Read this before running it.

    make stage7-final-test

This is the only entry point in the repository that reads the `final_test` split.
It refuses to run unless `reports/stage7/PREREGISTRATION.json` exists — that file
pins the final configuration hash and the exact metric list, written before any test
row was read.

Every opening is appended to `reports/stage7/TEST_SET_LEDGER.json`. Running this
twice does not produce two independent estimates; it produces one estimate and one
number that has seen the answer. If it must be re-run (a genuine bug), say so in the
report — the ledger will show it regardless.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.train.final_test import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
