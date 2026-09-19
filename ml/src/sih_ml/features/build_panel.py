"""Stage 2.2 — assemble the modelling panel (one row per labelled segment-day).

Output: data/processed/panel_v1.parquet  +  manifests/panel_v1.json

Joins, with a strict as-of / no-look-ahead contract:
  * static terrain / soil / lithology / land-cover  (segment_static_features.csv)
  * static hydrology                                (segment_hydrology_features.csv)
  * antecedent rainfall                             (CHIRPS, cutoff = date - horizon)
  * event-history counts                            (lagged >= min_history_lag_days)

No transformation / scaling / imputation is applied here — that happens inside the
CV loop (preprocess/transformers.py) to avoid train/test leakage.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from sih_ml.features.rainfall import build_cell_series, rainfall_features
from sih_ml.utils.common import (
    get_logger,
    hash_sources,
    load_config,
    resolve,
    set_seed,
    write_manifest,
)
from sih_ml.utils.geo import load_segment_centroids, nearest_cell_map

log = get_logger("panel")

FORECAST_HORIZON_DAYS = 1        # predict from rainfall known the day before
MIN_HISTORY_LAG_DAYS = 30        # event-history features may not see the last 30 d


SOIL_COLS = [
    "soil_clay_0_5cm_pct", "soil_sand_0_5cm_pct", "soil_silt_0_5cm_pct",
    "soil_soc_0_5cm_dg_kg", "soil_bdod_0_5cm_cg_cm3", "soil_cfvo_0_5cm_cm3_dm3",
    "soil_phh2o_0_5cm_ph10",
]


def clean_static(static: pd.DataFrame) -> pd.DataFrame:
    df = static.copy()
    # SoilGrids nodata arrives as an all-zero soil vector -> NaN + missingness flag
    zero_soil = (df[SOIL_COLS].abs().sum(axis=1) == 0)
    df["soil_is_missing"] = zero_soil.astype(int)
    df.loc[zero_soil, SOIL_COLS] = np.nan
    # SoilGrids integer conventions -> physical units (harmless for trees, sane for EDA)
    for c in ["soil_clay_0_5cm_pct", "soil_sand_0_5cm_pct", "soil_silt_0_5cm_pct"]:
        df[c] = df[c] / 10.0            # g/kg*10 -> %
    df["soil_bdod_0_5cm_cg_cm3"] = df["soil_bdod_0_5cm_cg_cm3"] / 100.0   # cg/cm3 -> g/cm3
    df["soil_phh2o_0_5cm_ph10"] = df["soil_phh2o_0_5cm_ph10"] / 10.0
    # circular aspect
    asp = np.radians(df["aspect_mean_deg"])
    df["aspect_sin"] = np.sin(asp)
    df["aspect_cos"] = np.cos(asp)
    df["landcover_class"] = df["landcover_class"].astype("Int64").astype(str)
    return df


def event_history_features(labels: pd.DataFrame, events: pd.DataFrame, centroids: pd.DataFrame) -> pd.DataFrame:
    """For each labelled (segment, date): count prior events within 10 km, using
    only events at least MIN_HISTORY_LAG_DAYS before the labelled date."""
    ev = events.dropna(subset=["lon", "lat", "date"]).copy()
    ev["date"] = pd.to_datetime(ev["date"])
    lab = labels.merge(centroids, on="segment_id", how="left")
    from sih_ml.utils.geo import haversine_m

    elon, elat, edate = ev.lon.to_numpy(), ev.lat.to_numpy(), ev.date.to_numpy()
    out = np.zeros((len(lab), 2))
    slon = lab.lon.to_numpy()
    slat = lab.lat.to_numpy()
    sdate = pd.to_datetime(lab.date).to_numpy()
    for i in range(len(lab)):
        if np.isnan(slon[i]):
            continue
        d = haversine_m(elon, elat, slon[i], slat[i])
        lag_days = (sdate[i] - edate) / np.timedelta64(1, "D")
        near = d <= 10_000
        out[i, 0] = np.sum(near & (lag_days >= MIN_HISTORY_LAG_DAYS) & (lag_days <= 365 + MIN_HISTORY_LAG_DAYS))
        out[i, 1] = np.sum(near & (lag_days >= MIN_HISTORY_LAG_DAYS))
    return pd.DataFrame(
        {"segment_id": lab.segment_id, "date": lab.date,
         "hist_events_1y_lag30": out[:, 0], "hist_events_all_lag30": out[:, 1]}
    )


def main(config_path: str | None = None) -> None:
    cfg = load_config(config_path)
    set_seed(cfg.seed)

    labels = pd.read_parquet(resolve(cfg, cfg.paths.processed) / "labels_v1.parquet")
    labels["date"] = pd.to_datetime(labels["date"]).dt.normalize()
    pairs = labels[["segment_id", "date"]].drop_duplicates().reset_index(drop=True)
    log.info("panel base: %d labelled segment-days", len(pairs))

    static = clean_static(pd.read_csv(resolve(cfg, cfg.paths.static_features)))
    hydro = pd.read_csv(resolve(cfg, cfg.paths.hydro_features))

    cache = resolve(cfg, cfg.paths.interim) / "segment_centroids.parquet"
    centroids = load_segment_centroids(resolve(cfg, cfg.paths.roads_gpkg),
                                       cfg.corridor.metric_crs, cache_path=cache)

    series, cells = build_cell_series(resolve(cfg, cfg.paths.chirps_csv))
    seg_cell = nearest_cell_map(centroids[centroids.segment_id.isin(pairs.segment_id)], cells)

    rain = rainfall_features(pairs, series, seg_cell, horizon_days=FORECAST_HORIZON_DAYS)

    events = pd.read_parquet(resolve(cfg, cfg.paths.interim) / "events_dedup_v1.parquet")
    hist = event_history_features(pairs, events, centroids)

    # road attributes from the roads csv
    roads = pd.read_csv(resolve(cfg, cfg.paths.roads_csv), low_memory=False,
                        dtype={"surface": "string", "highway": "string",
                               "bridge": "string", "tunnel": "string", "maxspeed": "string"})
    roads = roads[["segment_id", "highway", "surface", "bridge", "tunnel", "maxspeed", "length_m"]]
    for c in ("bridge", "tunnel"):
        roads[c] = roads[c].notna().astype(int)

    panel = (
        labels
        .merge(rain.drop(columns=["cell_id"], errors="ignore"), on=["segment_id", "date"], how="left")
        .merge(static, on="segment_id", how="left")
        .merge(hydro, on="segment_id", how="left")
        .merge(roads, on="segment_id", how="left")
        .merge(hist, on=["segment_id", "date"], how="left")
        .merge(seg_cell[["segment_id", "cell_dist_m"]], on="segment_id", how="left")
    )
    panel["month"] = panel["date"].dt.month
    panel["doy_sin"] = np.sin(2 * np.pi * panel["date"].dt.dayofyear / 365.25)
    panel["doy_cos"] = np.cos(2 * np.pi * panel["date"].dt.dayofyear / 365.25)
    panel["is_monsoon"] = panel["month"].isin([6, 7, 8, 9]).astype(int)

    out = resolve(cfg, cfg.paths.processed) / "panel_v1.parquet"
    panel.to_parquet(out, index=False)
    log.info("wrote %s  shape=%s", out, panel.shape)

    feat_cols = [c for c in panel.columns if c not in
                 ("segment_id", "date", "target", "label_tier", "label_confidence",
                  "hazard", "sample_weight", "label_source", "event_id",
                  "source_lon", "source_lat", "persist_day", "snap_dist_m",
                  "seg_lon", "seg_lat", "lon", "lat")]
    manifest = {
        "sources": hash_sources({
            "static": resolve(cfg, cfg.paths.static_features),
            "hydro": resolve(cfg, cfg.paths.hydro_features),
            "chirps": resolve(cfg, cfg.paths.chirps_csv),
            "labels_v1": resolve(cfg, cfg.paths.processed) / "labels_v1.parquet",
        }),
        "forecast_horizon_days": FORECAST_HORIZON_DAYS,
        "min_history_lag_days": MIN_HISTORY_LAG_DAYS,
        "n_rows": int(len(panel)),
        "n_positive": int((panel.target == 1).sum()),
        "n_negative": int((panel.target == 0).sum()),
        "n_features": len(feat_cols),
        "feature_columns": sorted(feat_cols),
        "null_fraction": panel[feat_cols].isna().mean().round(4).to_dict(),
        "chirps_cell_dist_m_p95": float(np.nanpercentile(panel["cell_dist_m"], 95)),
    }
    write_manifest(resolve(cfg, cfg.paths.manifests), "panel_v1", manifest)
    log.info("panel manifest written (%d features)", len(feat_cols))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
