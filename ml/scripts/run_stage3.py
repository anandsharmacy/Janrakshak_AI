#!/usr/bin/env python
"""Stage 3 — train + evaluate the baseline model.

    python scripts/run_stage3.py [conf/model_baseline.yaml]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.train.run_baseline import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
