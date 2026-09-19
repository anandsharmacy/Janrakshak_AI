"""Load the four disruption-event sources into one normalised event table.

Normalised schema (one row per reported hazard event):
    event_id, source, date (datetime64), lon, lat, hazard (str),
    location_accuracy_m (float), road_explicit (bool), raw_ref (str)
"""
from __future__ import annotations

import numpy as np
import pandas as pd

# GLC textual accuracy -> metres (COOLR location_accuracy field)
_GLC_ACC_M = {
    "exact": 100.0,
    "1km": 1_000.0,
    "5km": 5_000.0,
    "10km": 10_000.0,
    "25km": 25_000.0,
    "50km": 50_000.0,
    "100km": 100_000.0,
    "unknown": 50_000.0,
    np.nan: 50_000.0,
}


def _parse_dates(s: pd.Series) -> pd.Series:
    return pd.to_datetime(s, errors="coerce", utc=False).dt.tz_localize(None)


def load_glc(path) -> pd.DataFrame:
    df = pd.read_csv(path)
    out = pd.DataFrame(
        {
            "event_id": "GLC-" + df["event_id"].astype(str),
            "source": "coolr_glc",
            "date": _parse_dates(df["event_date"]).dt.normalize(),
            "lon": pd.to_numeric(df["longitude"], errors="coerce"),
            "lat": pd.to_numeric(df["latitude"], errors="coerce"),
            "hazard": df["landslide_category"].fillna("landslide").astype(str).str.lower(),
            "trigger": df["landslide_trigger"].fillna("unknown").astype(str).str.lower(),
            "location_accuracy_m": df["location_accuracy"].map(_GLC_ACC_M).fillna(50_000.0),
            "raw_ref": df["source_link"].astype(str),
        }
    )
    out["road_explicit"] = out["hazard"].str.contains("road")
    return out


def load_corridor_landslides(path) -> pd.DataFrame:
    df = pd.read_csv(path)
    # These already carry a nearest_segment_id + distance; accuracy is "place level".
    acc = np.where(df["location_accuracy"].astype(str).str.contains("exact"), 500.0, 15_000.0)
    out = pd.DataFrame(
        {
            "event_id": "CLS-" + df["landslide_id"].astype(str),
            "source": "corridor_landslides",
            "date": _parse_dates(df["event_date"]).dt.normalize(),
            "lon": pd.to_numeric(df["lon"], errors="coerce"),
            "lat": pd.to_numeric(df["lat"], errors="coerce"),
            "hazard": df["landslide_category"].fillna("landslide").astype(str).str.lower(),
            "trigger": df["landslide_trigger"].fillna("unknown").astype(str).str.lower(),
            "location_accuracy_m": acc,
            "raw_ref": df["source_url"].astype(str),
        }
    )
    out["road_explicit"] = out["hazard"].str.contains("road")
    return out


def load_disruption_events(path) -> pd.DataFrame:
    df = pd.read_csv(path)
    df = df[df["in_bbox"] == 1].copy()
    out = pd.DataFrame(
        {
            "event_id": "EVT-" + df["event_id"].astype(str),
            "source": "reliefweb_events",
            "date": _parse_dates(df["date"]).dt.normalize(),
            "lon": pd.to_numeric(df["lon"], errors="coerce"),
            "lat": pd.to_numeric(df["lat"], errors="coerce"),
            "hazard": df["hazard"].fillna("unknown").astype(str).str.lower(),
            "trigger": "unknown",
            "location_accuracy_m": np.where(df["place_hint"].notna(), 15_000.0, 30_000.0),
            "raw_ref": df["url"].astype(str),
        }
    )
    out["road_explicit"] = out["hazard"].str.contains("road")
    return out


def load_gold_segment_labels(path) -> pd.DataFrame:
    """The single verified (segment, date, disrupted) record — the gold anchor."""
    df = pd.read_csv(path)
    out = pd.DataFrame(
        {
            "event_id": "GOLD-" + df["event_id"].astype(str),
            "source": "verified_segment_label",
            "date": _parse_dates(df["date"]).dt.normalize(),
            "lon": pd.to_numeric(df["lon"], errors="coerce"),
            "lat": pd.to_numeric(df["lat"], errors="coerce"),
            "hazard": df["hazard"].astype(str).str.lower(),
            "trigger": "unknown",
            "location_accuracy_m": 200.0,
            "raw_ref": df["source_url"].astype(str),
            "verified_segment_id": df["segment_id"].astype(str),
        }
    )
    out["road_explicit"] = True
    return out


def load_all_events(cfg_paths) -> pd.DataFrame:
    frames = [
        load_glc(cfg_paths["glc_bbox"]),
        load_corridor_landslides(cfg_paths["corridor_landslides"]),
        load_disruption_events(cfg_paths["disruption_events"]),
        load_gold_segment_labels(cfg_paths["road_segment_labels"]),
    ]
    df = pd.concat(frames, ignore_index=True)
    if "verified_segment_id" not in df.columns:
        df["verified_segment_id"] = pd.NA
    return df
