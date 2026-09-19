#!/usr/bin/env python
"""Stage 9 — remediation of the four findings against final_v1.

    python scripts/run_stage9.py

Fixes the leak (A), the label-composition confound (B), the monotonicity bug (C),
then re-diagnoses steep terrain (D) and re-validates everything (E) with the same
rigor bar as Stage 7: paired significance across 5 folds x 3 seeds.

Produces `final_v2` under a NEW config hash. `final_v1` (5c8ab2326f9c5b5c) is left
in place as a documented known-leaked reference.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.train.run_remediate import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
