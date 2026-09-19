#!/usr/bin/env python
"""Stage 4 — train the model from scratch with the hardened training pipeline.

    python scripts/run_stage4.py                    # start (or auto-resume)
    python scripts/run_stage4.py conf/other.yaml    # alternate config

Resume is automatic: if `checkpoints/<model_version>/fold_k/fold_k_progress.json`
exists from an interrupted run, that fold resumes from its last periodic snapshot
instead of restarting. To force a clean run, delete the checkpoints directory.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from sih_ml.train.train_from_scratch import main

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
