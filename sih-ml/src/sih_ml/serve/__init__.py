"""Stage 11 — production inference.

Runtime dependencies are deliberately small: numpy, pandas (+pyarrow), lightgbm, pyyaml.
No scikit-learn and no pickles at serving time — calibrators ship as JSON lookup
tables. See DEPLOYMENT.md.
"""
