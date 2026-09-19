"""Antecedent-rainfall feature engineering from the CHIRPS daily corridor grid.

All windows for a labelled row (segment, date) are computed with a cutoff of
`date - forecast_horizon_days` and use only rainfall on days <= cutoff, so there
is no look-ahead. With horizon=1 the model predicts a disruption purely from
rainfall known the day before — the most defensible (leakage-free) framing.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

# NE-Himalaya intensity-duration threshold  I = c * D^(-b)   (I mm/hr, D hr)
# (J. Earth System Science 2025; TRMM-based, 2007-2016)
ID_C, ID_B = 5.8294, 0.4141
WINDOWS = (1, 3, 7, 15, 30)
API_DECAY = 0.92
API_N = 30


def build_cell_series(chirps_path) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return (long series indexed by cell_id/date, cell coordinate table)."""
    ch = pd.read_csv(chirps_path)
    ch["date"] = pd.to_datetime(ch["date"]).dt.normalize()
    ch["precip_mm"] = pd.to_numeric(ch["precip_mm"], errors="coerce").fillna(0.0).clip(lower=0)
    cells = ch[["cell_id", "latitude", "longitude"]].drop_duplicates().reset_index(drop=True)
    series = ch.pivot_table(index="date", columns="cell_id", values="precip_mm", aggfunc="mean")
    series = series.sort_index().asfreq("D").fillna(0.0)
    return series, cells


def _id_ratio(total_mm: float, duration_days: int) -> float:
    dur_hr = duration_days * 24.0
    i_obs = total_mm / dur_hr
    i_thr = ID_C * dur_hr ** (-ID_B)
    return i_obs / i_thr


def rainfall_features(pairs: pd.DataFrame, series: pd.DataFrame, seg_cell: pd.DataFrame,
                      horizon_days: int = 1) -> pd.DataFrame:
    """pairs: [segment_id, date]. Returns pairs + rainfall feature columns.

    Computed per (cell, cutoff-date) then broadcast to segments — cheap because
    there are ~130 cells and a few thousand distinct dates.
    """
    p = pairs.merge(seg_cell[["segment_id", "cell_id"]], on="segment_id", how="left")
    p["cutoff"] = pd.to_datetime(p["date"]).dt.normalize() - pd.Timedelta(days=horizon_days)

    # cumulative sum per cell for O(1) window sums
    csum = series.cumsum()
    idx = series.index
    pos = pd.Series(np.arange(len(idx)), index=idx)

    def win_sum(cell, cutoff, w):
        if cutoff not in pos.index:
            # snap to nearest earlier available date
            earlier = idx[idx <= cutoff]
            if len(earlier) == 0:
                return np.nan
            cutoff = earlier[-1]
        j = pos[cutoff]
        hi = csum[cell].iloc[j]
        lo = csum[cell].iloc[j - w] if j - w >= 0 else 0.0
        return float(hi - lo)

    feats = []
    cache: dict = {}
    for cell, cutoff in p[["cell_id", "cutoff"]].itertuples(index=False):
        key = (cell, cutoff)
        if key in cache:
            feats.append(cache[key])
            continue
        if pd.isna(cell) or cutoff > idx[-1]:
            # Beyond the end of the CHIRPS record there is no rainfall to report.
            # This used to fall through to win_sum's "snap to nearest earlier date",
            # which silently gave every 2026 row the dry-season window ending
            # 2025-12-31 — 4,913 panel_v1 rows with ~0 mm of rain, most of them
            # monsoon-dated negatives (Stage 10, data-integrity finding D1).
            row = {f"rain_{w}d_mm": np.nan for w in WINDOWS}
        else:
            row = {f"rain_{w}d_mm": win_sum(cell, cutoff, w) for w in WINDOWS}
            # API (decayed sum of last API_N days)
            if cutoff in pos.index or len(idx[idx <= cutoff]):
                cc = cutoff if cutoff in pos.index else idx[idx <= cutoff][-1]
                j = pos[cc]
                lastN = series[cell].iloc[max(0, j - API_N + 1): j + 1].to_numpy()
                k = np.arange(len(lastN))[::-1]
                row["api_mm"] = float(np.sum(lastN * API_DECAY ** k))
                # days since rain > 1 mm
                recent = series[cell].iloc[max(0, j - 60): j + 1]
                wet = np.where(recent.to_numpy() > 1.0)[0]
                row["days_since_rain"] = int(len(recent) - 1 - wet[-1]) if len(wet) else 60
                row["rain_max_1d_in_3d_mm"] = float(series[cell].iloc[max(0, j - 2): j + 1].max())
            else:
                row["api_mm"] = np.nan
                row["days_since_rain"] = np.nan
                row["rain_max_1d_in_3d_mm"] = np.nan
            # ID-threshold exceedance ratios
            for w in (1, 3, 7):
                tot = row[f"rain_{w}d_mm"]
                row[f"id_ratio_{w}d"] = _id_ratio(tot, w) if pd.notna(tot) else np.nan
                row[f"id_exceed_{w}d"] = float(row[f"id_ratio_{w}d"] > 1.0) if pd.notna(tot) else np.nan
        cache[key] = row
        feats.append(row)

    fdf = pd.DataFrame(feats, index=p.index)
    out = pd.concat([p.drop(columns=["cutoff"]), fdf], axis=1)
    return out
