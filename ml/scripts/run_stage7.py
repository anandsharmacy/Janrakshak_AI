#!/usr/bin/env python
"""Stage 7 — accuracy optimization.

    python scripts/run_stage7.py                     # full arm ladder
    python scripts/run_stage7.py conf/other.yaml

Does NOT open the locked `final_test`. It ends by freezing the winning
configuration into reports/stage7/PREREGISTRATION.json; `scripts/open_final_test.py`
is the only code that reads the locked split, and it refuses to run without that
file.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.train.run_optimize import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
