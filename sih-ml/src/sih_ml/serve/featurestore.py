"""Feature store for corridor-wide inference.

Training features came from one panel row per labelled segment-day. Serving needs the
same 45 features for EVERY corridor segment (309,042) on one day. The inference
input splits cleanly into three blocks with very different change rates:

    static   (27 cols)  terrain, soil, hydrology, road — changes when sources change
    rainfall (14 cols)  CHIRPS windows — changes daily, but only per CHIRPS CELL (132)
    season    (4 cols)  month / day-of-year — one scalar per day

So the store precomputes the static block ONCE as a numeric matrix with categoricals
already encoded to the model's level indices, computes the rainfall block per cell,
and fills a preallocated buffer with a single gather. That is the whole
preprocessing optimization, and it is only safe because parity with the training
panel is tested row-for-row (tests/test_serve.py::test_feature_parity_with_panel).

Every transform here REUSES the Stage 2 code path (`clean_static`,
`rainfall_features`, `nearest_cell_map`) and mirrors `models.dataset.load_data`'s
dtype handling. Nothing is reimplemented that could drift from training.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.features.build_panel import clean_static
from sih_ml.features.rainfall import build_cell_series, rainfall_features
from sih_ml.utils.common import REPO_ROOT, load_config, resolve
from sih_ml.utils.geo import nearest_cell_map

HORIZON_DAYS = 1                  # the model predicts from rainfall known the day before
HISTORY_DAYS = 61                 # days_since_rain looks back 60 days from the cutoff
RAIN_COLS = ["rain_1d_mm", "rain_3d_mm", "rain_7d_mm", "rain_15d_mm", "rain_30d_mm",
             "rain_max_1d_in_3d_mm", "api_mm", "days_since_rain", "id_ratio_1d",
             "id_ratio_3d", "id_ratio_7d", "id_exceed_1d", "id_exceed_3d", "id_exceed_7d"]
SEASON_COLS = ["month", "doy_sin", "doy_cos", "is_monsoon"]


def feature_groups(features: list[str]) -> dict:
    return {"rainfall_cols": [c for c in features if c in RAIN_COLS],
            "season_cols": [c for c in features if c in SEASON_COLS],
            "static_cols": [c for c in features if c not in RAIN_COLS + SEASON_COLS],
            "horizon_days": HORIZON_DAYS, "history_days": HISTORY_DAYS}


def season_values(date: pd.Timestamp) -> dict:
    d = pd.Timestamp(date)
    doy = d.dayofyear
    return {"month": float(d.month), "doy_sin": float(np.sin(2 * np.pi * doy / 365.25)),
            "doy_cos": float(np.cos(2 * np.pi * doy / 365.25)),
            "is_monsoon": float(d.month in (6, 7, 8, 9))}


def encode_categorical(values: pd.Series, levels: list[str], missing_token: str) -> np.ndarray:
    """Level index as float, unseen -> NaN — what LightGBM does to a pandas categorical
    at predict time (`_data_from_pandas` re-categorises onto the training levels)."""
    s = values.astype("string").fillna(missing_token)
    idx = pd.Index(levels).get_indexer(s.to_numpy(dtype=object))
    out = idx.astype(float)
    out[idx < 0] = np.nan
    return out


def _sources(pcfg) -> dict[str, Path]:
    return {"static": resolve(pcfg, pcfg.paths.static_features),
            "hydro": resolve(pcfg, pcfg.paths.hydro_features),
            "roads": resolve(pcfg, pcfg.paths.roads_csv),
            "centroids": resolve(pcfg, pcfg.paths.interim) / "segment_centroids.parquet",
            "chirps": resolve(pcfg, pcfg.paths.chirps_csv)}


def _sha(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# --------------------------------------------------------------------------- #
def static_table(pcfg=None) -> pd.DataFrame:
    """One row per corridor segment, the panel's static columns + its CHIRPS cell.
    Same sources and same joins as features/build_panel.main."""
    pcfg = pcfg or load_config()
    src = _sources(pcfg)
    static = clean_static(pd.read_csv(src["static"]))
    hydro = pd.read_csv(src["hydro"])
    roads = pd.read_csv(src["roads"], low_memory=False,
                        dtype={"surface": "string", "highway": "string",
                               "bridge": "string", "tunnel": "string", "maxspeed": "string"})
    roads = roads[["segment_id", "highway", "surface", "bridge", "tunnel", "maxspeed", "length_m"]]
    for c in ("bridge", "tunnel"):
        roads[c] = roads[c].notna().astype(int)
    cent = pd.read_parquet(src["centroids"])
    _, cells = build_cell_series(src["chirps"])
    seg_cell = nearest_cell_map(cent, cells)
    for name, df in (("static", static), ("hydro", hydro), ("roads", roads)):
        if df.segment_id.duplicated().any():
            raise ValueError(f"{name} source has duplicate segment_id rows")
    # centroid coordinates ride along for the Supabase publisher (not model inputs)
    return (cent[["segment_id", "lon", "lat"]]
            .rename(columns={"lon": "centroid_lon", "lat": "centroid_lat"})
            .merge(static, on="segment_id", how="left")
            .merge(hydro, on="segment_id", how="left")
            .merge(roads, on="segment_id", how="left")
            .merge(seg_cell, on="segment_id", how="left"))


class FeatureStore:
    def __init__(self, segment_ids: np.ndarray, static_matrix: np.ndarray, cell_ids: np.ndarray,
                 cell_index: np.ndarray, slope: np.ndarray, rain_series: pd.DataFrame,
                 schema: dict, manifest: dict, lonlat: np.ndarray | None = None):
        self.segment_ids = segment_ids
        self.static_matrix = static_matrix          # n_seg x n_features, float64, rain/season = NaN
        self.cell_ids = cell_ids                    # unique CHIRPS cells, order of cell_index
        self.cell_index = cell_index                # n_seg -> position in cell_ids
        self.slope = slope
        self.lonlat = lonlat                        # n_seg x 2 centroid lon/lat, or None
        self.rain = rain_series                     # date x cell_id, daily mm
        self.schema, self.manifest = schema, manifest
        self._pos = pd.Index(segment_ids)
        f = schema["features"]
        self.rain_idx = np.array([f.index(c) for c in schema["rainfall_cols"]])
        self.season_idx = np.array([f.index(c) for c in schema["season_cols"]])
        self._buf: np.ndarray | None = None

    # ------------------------------------------------------------ build / io
    @classmethod
    def build(cls, schema: dict, pcfg=None) -> "FeatureStore":
        pcfg = pcfg or load_config()
        t = static_table(pcfg)
        feats = schema["features"]
        M = np.full((len(t), len(feats)), np.nan)
        for j, c in enumerate(feats):
            if c in schema["categorical"]:
                M[:, j] = encode_categorical(t[c], schema["category_levels"][c],
                                             schema["missing_category_token"])
            elif c in schema["static_cols"]:
                M[:, j] = pd.to_numeric(t[c], errors="coerce").to_numpy(float)
        series, _ = build_cell_series(_sources(pcfg)["chirps"])
        cell_ids = np.array(sorted(t.cell_id.dropna().unique()))
        cell_index = pd.Index(cell_ids).get_indexer(t.cell_id.to_numpy())
        if (cell_index < 0).any():
            raise ValueError("segments without a CHIRPS cell")
        manifest = {"n_segments": int(len(t)), "n_cells": int(len(cell_ids)),
                    "rain_first": str(series.index.min().date()),
                    "rain_last": str(series.index.max().date()),
                    "sources": {k: _sha(p) for k, p in _sources(pcfg).items()},
                    "schema_sha256": hashlib.sha256(json.dumps(schema, sort_keys=True)
                                                    .encode()).hexdigest(),
                    "built_utc": pd.Timestamp.now(tz="UTC").isoformat()}
        return cls(t.segment_id.to_numpy(), M, cell_ids, cell_index,
                   t["slope_mean_deg"].to_numpy(float), series[list(cell_ids)], schema, manifest,
                   lonlat=t[["centroid_lon", "centroid_lat"]].to_numpy(float))

    def save(self, d: str | Path) -> Path:
        d = Path(d)
        d.mkdir(parents=True, exist_ok=True)
        np.save(d / "static_matrix.npy", self.static_matrix)
        seg = pd.DataFrame({"segment_id": self.segment_ids, "cell_index": self.cell_index,
                            "slope_mean_deg": self.slope})
        if self.lonlat is not None:
            seg["lon"], seg["lat"] = self.lonlat[:, 0], self.lonlat[:, 1]
        seg.to_parquet(d / "segments.parquet", index=False)
        self.rain.to_parquet(d / "rainfall.parquet")
        (d / "manifest.json").write_text(json.dumps({**self.manifest,
                                                     "cell_ids": list(map(str, self.cell_ids))},
                                                    indent=1))
        return d

    @classmethod
    def load(cls, d: str | Path, schema: dict, mmap: bool = True) -> "FeatureStore":
        d = Path(d)
        man = json.loads((d / "manifest.json").read_text())
        want = hashlib.sha256(json.dumps(schema, sort_keys=True).encode()).hexdigest()
        if man["schema_sha256"] != want:
            raise ValueError("feature store was built for a different model schema — rebuild it")
        seg = pd.read_parquet(d / "segments.parquet")
        M = np.load(d / "static_matrix.npy", mmap_mode="r" if mmap else None)
        rain = pd.read_parquet(d / "rainfall.parquet")
        rain.index = pd.DatetimeIndex(rain.index)
        lonlat = seg[["lon", "lat"]].to_numpy(float) if {"lon", "lat"} <= set(seg.columns) else None
        return cls(seg.segment_id.to_numpy(), M, np.array(man["cell_ids"]),
                   seg.cell_index.to_numpy(), seg.slope_mean_deg.to_numpy(float), rain,
                   schema, man, lonlat=lonlat)

    def stale_sources(self, pcfg=None) -> list[str]:
        """Sources whose content changed since the store was built."""
        pcfg = pcfg or load_config()
        return [k for k, p in _sources(pcfg).items()
                if k != "chirps" and self.manifest["sources"].get(k) != _sha(p)]

    # ---------------------------------------------------------------- rainfall
    @property
    def rain_end(self) -> pd.Timestamp:
        return pd.Timestamp(self.rain.index.max())

    @property
    def rain_start(self) -> pd.Timestamp:
        return pd.Timestamp(self.rain.index.min())

    def append_rainfall(self, day_values: pd.DataFrame) -> None:
        """Add new days (index = date, columns = cell_id) from the operational feed."""
        day_values = day_values.reindex(columns=self.rain.columns)
        if day_values.isna().any().any():
            raise ValueError("new rainfall days must cover every cell")
        self.rain = pd.concat([self.rain[~self.rain.index.isin(day_values.index)],
                               day_values]).sort_index().asfreq("D")

    def rainfall_by_cell(self, date: pd.Timestamp) -> np.ndarray:
        """n_cells x len(rainfall_cols), computed by the Stage 2 function itself."""
        pairs = pd.DataFrame({"segment_id": self.cell_ids, "date": pd.Timestamp(date)})
        seg_cell = pd.DataFrame({"segment_id": self.cell_ids, "cell_id": self.cell_ids})
        out = rainfall_features(pairs, self.rain, seg_cell, HORIZON_DAYS)
        return out[self.schema["rainfall_cols"]].to_numpy(float)

    # ------------------------------------------------------------------ matrix
    def matrix(self, date: pd.Timestamp, rows: np.ndarray | None = None) -> np.ndarray:
        """Model-ready matrix for `date` (all segments, or the given row positions)."""
        cell_rain = self.rainfall_by_cell(date)
        if rows is None:
            if self._buf is None:
                self._buf = np.empty(self.static_matrix.shape)
            X = self._buf
            X[:] = self.static_matrix
            ci = self.cell_index
        else:
            X = np.array(self.static_matrix[rows])
            ci = self.cell_index[rows]
        X[:, self.rain_idx] = cell_rain[ci]
        sv = season_values(date)
        for j, c in zip(self.season_idx, self.schema["season_cols"]):
            X[:, j] = sv[c]
        return X

    def positions(self, segment_ids) -> tuple[np.ndarray, list[str]]:
        idx = self._pos.get_indexer(np.asarray(segment_ids, dtype=object))
        missing = [s for s, i in zip(segment_ids, idx) if i < 0]
        return idx[idx >= 0], missing


def rainfall_from_history(history_mm: np.ndarray, date: pd.Timestamp, cols: list[str]) -> np.ndarray:
    """Rainfall features from a caller-supplied daily history (what-if / forecast
    scoring). `history_mm` holds HISTORY_DAYS values, oldest first, ending on the
    cutoff day (date - 1). Uses the same Stage 2 function as training."""
    cutoff = pd.Timestamp(date) - pd.Timedelta(days=HORIZON_DAYS)
    idx = pd.date_range(end=cutoff, periods=len(history_mm), freq="D")
    series = pd.DataFrame({"h": np.asarray(history_mm, float)}, index=idx)
    out = rainfall_features(pd.DataFrame({"segment_id": ["h"], "date": [pd.Timestamp(date)]}),
                            series, pd.DataFrame({"segment_id": ["h"], "cell_id": ["h"]}),
                            HORIZON_DAYS)
    return out[cols].to_numpy(float)[0]


def default_store_dir() -> Path:
    return REPO_ROOT / "deploy" / "featurestore"
