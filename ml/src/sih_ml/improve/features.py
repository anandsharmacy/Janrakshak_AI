"""Stage 10 data-side changes: rainfall coverage mask and climate-relative rainfall.

Coverage mask (D1)
------------------
panel_v1 carries 4,913 rows dated 2026. CHIRPS ends 2025-12-31, and the Stage 2
rainfall builder snapped any cutoff past the end of the record back to the last
available day — so those rows carry the dry-season window ending 2025-12-31 (median
7-day rain 0 mm, ~53 days since rain) even when they are dated in the monsoon. In dev
all 4,463 of them are negatives. A monsoon day with no rain is a fabricated easy
negative: it teaches "dry => safe" from rows whose dryness is an artifact. The mask
removes every row whose rainfall cutoff lies beyond the record.

It was expected to inflate dev AP as well. Measured, it does not (Stage 10 report,
D1): easy negatives rank at the bottom, and AP depends only on how positives rank,
so removing them moves the champion's dev AP by ~0.0002. The fix is adopted as a
correctness fix — fabricated rows are wrong regardless — not as an accuracy gain.

Climate-relative rainfall (X3)
------------------------------
Stage 9 root-caused the steep-terrain gate failures to REGION TRANSFER: steep ROC
~0.75 in dev regions vs 0.63 in the held-out one. One physical mechanism for that is
that an absolute rainfall total means different things in different climates — a
100 mm week is ordinary in a wet valley and extreme in a dry one, and landslide
thresholds are routinely normalised by local climate for exactly this reason. The
features here express each window as its PERCENTILE within the row's own CHIRPS
cell's climatology, so "how unusual is this rain here" travels between regions even
if "how much rain" does not.

Leakage: the climatology uses rainfall only — no label enters it — over a fixed
reference period (2005-2014) so the normalisation does not change over the backtest.
The percentile is a monotone non-decreasing function of the window total for a fixed
cell, so the features carry the same monotone-increasing constraint as their parents
and `recompute()` lets the monotonicity check scale rain and re-derive them.
"""
from __future__ import annotations

from functools import lru_cache

import numpy as np
import pandas as pd

from sih_ml.features.rainfall import build_cell_series
from sih_ml.models.dataset import Data
from sih_ml.utils.common import Config, REPO_ROOT, resolve
from sih_ml.utils.geo import nearest_cell_map

FORECAST_HORIZON_DAYS = 1
PCTL_WINDOWS = (3, 7, 30)


def pctl_col(w: int) -> str:
    return f"rain_{w}d_pctl_local"


@lru_cache(maxsize=2)
def _series(chirps_csv: str) -> tuple[pd.DataFrame, pd.DataFrame]:
    return build_cell_series(chirps_csv)


def chirps_path(cfg: Config | None = None) -> str:
    """The CHIRPS file is a Stage 2 input, so it lives in the pipeline config
    (conf/config.yaml), not in the model-config chain."""
    from sih_ml.utils.common import load_config
    pc = load_config()
    return str(resolve(pc, pc.paths.chirps_csv))


def rainfall_coverage_end(cfg: Config) -> pd.Timestamp:
    series, _ = _series(chirps_path(cfg))
    return pd.Timestamp(series.index.max())


def coverage_mask(data: Data, cfg: Config) -> np.ndarray:
    """True where the row's rainfall cutoff (date - horizon) lies inside the record."""
    end = rainfall_coverage_end(cfg)
    cutoff = pd.to_datetime(data.panel["date"]).dt.normalize() - pd.Timedelta(
        days=FORECAST_HORIZON_DAYS)
    return (cutoff <= end).to_numpy()


class LocalRainPercentiles:
    """Per-cell empirical CDF of w-day rainfall totals over a reference period."""

    def __init__(self, cfg: Config, ref_start: str = "2005-01-01",
                 ref_end: str = "2014-12-31", windows=PCTL_WINDOWS):
        series, cells = _series(chirps_path(cfg))
        ref = series.loc[ref_start:ref_end]
        self.windows = tuple(windows)
        self.ref_period = (ref_start, ref_end)
        self.cdf: dict[tuple[str, int], np.ndarray] = {}
        for w in self.windows:
            roll = ref.rolling(w).sum().iloc[w - 1:]
            for c in ref.columns:
                self.cdf[(c, w)] = np.sort(roll[c].to_numpy(float))
        cent = pd.read_parquet(REPO_ROOT / "data" / "interim" / "segment_centroids.parquet")
        self.seg_cell = nearest_cell_map(cent, cells).set_index("segment_id")["cell_id"]

    def cells_for(self, panel: pd.DataFrame) -> np.ndarray:
        return self.seg_cell.reindex(panel["segment_id"].to_numpy()).to_numpy()

    def percentiles(self, rain: np.ndarray, cells: np.ndarray, w: int) -> np.ndarray:
        out = np.full(len(rain), np.nan)
        for c in pd.unique(cells):
            m = cells == c
            a = self.cdf.get((c, w))
            if a is None or not len(a):
                continue
            v = rain[m]
            ok = np.isfinite(v)
            r = np.full(m.sum(), np.nan)
            r[ok] = np.searchsorted(a, v[ok], side="right") / len(a)
            out[m] = r
        return out

    def add_to(self, data: Data) -> Data:
        """A copy of `data` with the percentile columns added as model features."""
        panel = data.panel.copy()
        cells = self.cells_for(panel)
        panel["_rain_cell"] = cells
        for w in self.windows:
            panel[pctl_col(w)] = self.percentiles(
                panel[f"rain_{w}d_mm"].to_numpy(float), cells, w)
        new = Data(panel=panel, features=[*data.features, *self.columns],
                   categorical=data.categorical, spec=data.spec)
        if getattr(data, "scope_mask_", None) is not None:
            new.apply_scope(data.scope_mask_)
        return new

    @property
    def columns(self) -> list[str]:
        return [pctl_col(w) for w in self.windows]

    def recompute(self, X: pd.DataFrame, panel: pd.DataFrame) -> pd.DataFrame:
        """Re-derive the percentile columns of X from its (possibly scaled) rainfall."""
        cells = panel.loc[X.index, "_rain_cell"].to_numpy()
        for w in self.windows:
            if pctl_col(w) in X:
                X[pctl_col(w)] = self.percentiles(X[f"rain_{w}d_mm"].to_numpy(float), cells, w)
        return X
