#!/usr/bin/env python
"""Stage 5 — evaluation + error analysis on held-out data.

    python scripts/run_stage5.py [conf/train_config.yaml]

Does NOT touch the locked `final_test` split.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.eval.run_error_analysis import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
