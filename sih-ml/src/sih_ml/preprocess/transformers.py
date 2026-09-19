"""In-fold preprocessing. Every transformer here is fit on the TRAINING fold only
and applied to val/test — this is the leakage firewall for Stage 3+.

Two builders:
  build_tree_pipeline()   -> minimal: pass NaN through, native categoricals for LightGBM
  build_linear_pipeline() -> impute + scale + one-hot, for the logistic baseline
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import yaml
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from sih_ml.utils.common import REPO_ROOT


def load_feature_spec(path: str | Path | None = None) -> dict:
    path = Path(path) if path else REPO_ROOT / "conf" / "feature_spec.yaml"
    with open(path) as f:
        return yaml.safe_load(f)


def model_feature_columns(spec: dict) -> list[str]:
    return (spec["numeric"] + spec["cyclic"] + spec["flag"] + spec["categorical"])


def split_X_y_w(panel: pd.DataFrame, spec: dict):
    cols = model_feature_columns(spec)
    X = panel[cols].copy()
    y = panel[spec["target"]].astype(int).to_numpy()
    w = panel["sample_weight"].to_numpy() if "sample_weight" in panel else np.ones(len(panel))
    return X, y, w


def build_tree_pipeline(spec: dict) -> tuple[Pipeline, dict]:
    """LightGBM/XGBoost want raw values + NaN. We only cast categoricals to a
    pandas 'category' dtype and coerce numerics. Returns (transformer, fit_params_hint)."""
    cat = spec["categorical"]
    num = spec["numeric"] + spec["cyclic"] + spec["flag"]

    def _prep(df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        for c in num:
            df[c] = pd.to_numeric(df[c], errors="coerce")
        for c in cat:
            df[c] = df[c].astype("string").fillna("__missing__").astype("category")
        return df

    from sklearn.preprocessing import FunctionTransformer

    pipe = Pipeline([("prep", FunctionTransformer(_prep, feature_names_out="one-to-one"))])
    return pipe, {"categorical_feature": cat}


def build_linear_pipeline(spec: dict) -> ColumnTransformer:
    num = spec["numeric"] + spec["cyclic"]
    flag = spec["flag"]
    cat = spec["categorical"]
    return ColumnTransformer(
        [
            ("num", Pipeline([("imp", SimpleImputer(strategy="median")),
                              ("sc", StandardScaler())]), num),
            ("flag", SimpleImputer(strategy="most_frequent"), flag),
            ("cat", Pipeline([("imp", SimpleImputer(strategy="constant", fill_value="__missing__")),
                              ("oh", OneHotEncoder(handle_unknown="ignore", min_frequency=20,
                                                   sparse_output=False))]), cat),
        ],
        remainder="drop",
        verbose_feature_names_out=True,
    )


def iter_spatial_folds(panel: pd.DataFrame, folds: pd.DataFrame, n_folds: int):
    """Yield (fold_idx, train_idx, val_idx) honouring the buffer zone.

    train excludes rows marked 'buffer' for that fold; val is the held-out block.
    """
    m = panel.merge(folds, on=["segment_id", "date"], how="left", suffixes=("", "_f"))
    for f in range(n_folds):
        role = m[f"spatial_role_f{f}"].to_numpy()
        tr = np.where(role == "train")[0]
        va = np.where(role == "val")[0]
        yield f, tr, va
