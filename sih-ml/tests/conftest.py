import sys
from pathlib import Path

import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from sih_ml.utils.common import load_config, resolve  # noqa: E402


@pytest.fixture(scope="session")
def cfg():
    return load_config()


@pytest.fixture(scope="session")
def labels(cfg):
    return pd.read_parquet(resolve(cfg, cfg.paths.processed) / "labels_v1.parquet")


@pytest.fixture(scope="session")
def panel(cfg):
    return pd.read_parquet(resolve(cfg, cfg.paths.processed) / "panel_v1.parquet")


@pytest.fixture(scope="session")
def folds(cfg):
    return pd.read_parquet(resolve(cfg, cfg.paths.processed) / "folds_v1.parquet")


@pytest.fixture(scope="session")
def events(cfg):
    return pd.read_parquet(resolve(cfg, cfg.paths.interim) / "events_dedup_v1.parquet")
