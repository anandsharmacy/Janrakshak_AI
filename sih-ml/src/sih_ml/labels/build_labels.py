"""Stage 2.1 — build the tiered label table (positives + strong negatives).

Output: data/processed/labels_v1.parquet  +  manifests/labels_v1.json

Row schema:
    segment_id, date, target (0/1), label_tier, label_confidence, hazard,
    sample_weight, label_source, event_id, source_lon, source_lat

Positives come from four event sources (COOLR/GLC, corridor landslides, reliefweb
corridor events, the one verified segment label) plus Dartmouth flood polygons.
Negatives are drawn from a low-susceptibility, hazard-excluded segment pool on
season-matched dates (case-control design). See DATA_DECISIONS.md.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from sih_ml.labels.events import load_all_events
from sih_ml.utils.common import (
    Config,
    check_sources_lock,
    get_logger,
    hash_sources,
    load_config,
    resolve,
    set_seed,
    write_manifest,
)
from sih_ml.utils.geo import haversine_m, load_segment_centroids, segments_within

log = get_logger("labels")


# --------------------------------------------------------------------------- #
# Susceptibility proxy (static, model-free) — used only to pick negatives
# --------------------------------------------------------------------------- #
_LITHO_RISK = {  # coarse GSI-code landslide susceptibility weight in [0, 1]
    "su": 0.9,   # Siwalik / Sub-Himalaya weak sediments — highly slide-prone
    "mt": 0.85,  # metamorphics (Higher/Lesser Himalaya)
    "sm": 0.8, "sc": 0.8, "ss": 0.75,
    "pa": 0.15,  # alluvium / plains
    "wb": 0.05,  # water body
}


def _litho_weight(code: str) -> float:
    c = str(code).lower()
    for pref, w in _LITHO_RISK.items():
        if c.startswith(pref):
            return w
    return 0.5


def build_susceptibility(static: pd.DataFrame, hydro: pd.DataFrame) -> pd.DataFrame:
    df = static.merge(hydro[["segment_id", "distance_to_nearest_river_m"]], on="segment_id", how="left")

    def z(s):
        s = pd.to_numeric(s, errors="coerce")
        return (s - s.mean()) / (s.std() + 1e-9)

    score = (
        1.2 * z(df["slope_mean_deg"])
        + 0.8 * z(df["slope_max_deg"])
        + 0.6 * z(-np.log1p(df["distance_to_nearest_river_m"].clip(lower=0)))
        + 1.0 * (df["lithology_class"].map(_litho_weight) - 0.5)
    )
    out = pd.DataFrame({"segment_id": df["segment_id"], "susceptibility": score})
    out["susceptibility_q"] = out["susceptibility"].rank(pct=True)
    return out


# --------------------------------------------------------------------------- #
# Event filtering + dedup
# --------------------------------------------------------------------------- #
def filter_events(ev: pd.DataFrame, cfg: Config) -> pd.DataFrame:
    lc = cfg.labels
    n0 = len(ev)
    ev = ev.dropna(subset=["date"]).copy()

    # temporal gate
    ev = ev[(ev.date >= pd.Timestamp(lc.min_event_date)) & (ev.date <= pd.Timestamp(lc.max_event_date))]

    # corridor bbox (keep rows with no coords only if a verified segment is attached)
    c = cfg.corridor
    in_bbox = (
        ev.lon.between(c.min_lon, c.max_lon) & ev.lat.between(c.min_lat, c.max_lat)
    )
    ev = ev[in_bbox | ev.verified_segment_id.notna()]

    # hazard keep / drop (substring)
    hz = ev.hazard.fillna("").str.lower()
    keep = hz.apply(lambda h: any(k in h for k in lc.keep_hazards))
    drop = hz.apply(lambda h: any(k in h for k in lc.drop_hazards))
    ev = ev[keep & ~drop]

    # GLC rain-trigger filter (only applies to the coolr source)
    is_glc = ev.source.eq("coolr_glc")
    trig_ok = ev.trigger.fillna("unknown").apply(lambda t: any(k in t for k in lc.glc_keep_triggers))
    ev = ev[~is_glc | trig_ok]

    # location accuracy cap (verified rows exempt)
    ev = ev[(ev.location_accuracy_m <= lc.max_location_accuracy_m) | ev.verified_segment_id.notna()]

    log.info("event filter: %d -> %d rows", n0, len(ev))
    return ev.reset_index(drop=True)


def dedup_events(ev: pd.DataFrame, cfg: Config) -> pd.DataFrame:
    """Greedy spatio-temporal dedup. Keeps the most precise (smallest accuracy) row
    of each cluster and records merged ids."""
    lc = cfg.labels
    ev = ev.sort_values(["location_accuracy_m", "date"]).reset_index(drop=True)
    used = np.zeros(len(ev), dtype=bool)
    keep_rows = []
    lon = ev.lon.to_numpy()
    lat = ev.lat.to_numpy()
    dt = ev.date.to_numpy()
    for i in range(len(ev)):
        if used[i]:
            continue
        same_time = np.abs((dt - dt[i]) / np.timedelta64(1, "D")) <= lc.dedup_days
        if np.isnan(lon[i]):
            dist_ok = np.zeros(len(ev), dtype=bool)
            dist_ok[i] = True
        else:
            dist_ok = haversine_m(lon, lat, lon[i], lat[i]) <= lc.dedup_metres
        grp = same_time & dist_ok & ~used
        grp[i] = True
        members = ev.loc[grp, "event_id"].tolist()
        row = ev.loc[i].to_dict()
        row["merged_event_ids"] = ";".join(members)
        row["n_merged"] = int(grp.sum())
        keep_rows.append(row)
        used |= grp
    out = pd.DataFrame(keep_rows)
    log.info("dedup: %d -> %d events", len(ev), len(out))
    return out


# --------------------------------------------------------------------------- #
# Tiering
# --------------------------------------------------------------------------- #
def assign_tier(row) -> str:
    acc = row["location_accuracy_m"]
    if row["source"] == "verified_segment_label":
        return "gold"
    if row.get("road_explicit") and acc <= 1_000:
        return "gold"
    if acc <= 5_000:
        return "silver"
    return "bronze"


# --------------------------------------------------------------------------- #
# Snap events -> segment-days
# --------------------------------------------------------------------------- #
def snap_positives(ev: pd.DataFrame, centroids: pd.DataFrame, cfg: Config,
                   susc: pd.DataFrame | None = None) -> pd.DataFrame:
    lc = cfg.labels
    susc_q = (susc.set_index("segment_id")["susceptibility_q"].to_dict() if susc is not None else {})
    rows = []
    for _, e in ev.iterrows():
        tier = assign_tier(e)
        prior = cfg.labels.tier_prior[tier]
        persist = range(0, lc.persistence_days + 1)
        is_landslide = "landslide" in str(e.hazard) or "slide" in str(e.hazard) or "debris" in str(e.hazard)

        if pd.notna(e.get("verified_segment_id")):
            segs = pd.DataFrame({"segment_id": [e["verified_segment_id"]], "dist_m": [0.0]})
        elif np.isnan(e.lon):
            continue
        else:
            radius = max(e.location_accuracy_m, lc.min_snap_radius_m)
            segs = segments_within(centroids, e.lon, e.lat, radius, lc.max_candidate_segments)
        if segs.empty:
            continue

        radius = max(e.location_accuracy_m, lc.min_snap_radius_m)
        for _, s in segs.iterrows():
            decay = float(np.exp(-s.dist_m / radius))
            # resolve location ambiguity toward terrain that can actually fail:
            # for landslides, up/down-weight a candidate by its static susceptibility
            sfac = 1.0
            if is_landslide and s.segment_id in susc_q and pd.notna(s.dist_m) and s.dist_m > 100:
                sfac = 0.5 + susc_q[s.segment_id]        # in [0.5, 1.5]
            conf = min(1.0, prior * decay * sfac)
            for k in persist:
                rows.append(
                    {
                        "segment_id": s.segment_id,
                        "date": (e.date + pd.Timedelta(days=k)).normalize(),
                        "target": 1,
                        "label_tier": tier,
                        "label_confidence": round(conf * (1.0 if k == 0 else 0.8), 4),
                        "hazard": e.hazard,
                        "label_source": e.source,
                        "event_id": e.event_id,
                        "source_lon": e.lon,
                        "source_lat": e.lat,
                        "persist_day": k,
                        "snap_dist_m": round(float(s.dist_m), 1),
                    }
                )
    pos = pd.DataFrame(rows)
    log.info("snapped positives: %d segment-day rows from %d events", len(pos), len(ev))
    return pos


def flood_polygon_positives(cfg: Config, centroids: pd.DataFrame,
                            rng: np.random.Generator) -> pd.DataFrame:
    """Segments whose centroid falls inside a dated Dartmouth flood polygon.

    Disabled by default (cfg.flood_polygons.enabled). When on: only the first
    `span_days` of each event are labelled and at most `max_segments_per_polygon`
    segments are kept, so the positive count stays bounded. Centroid-in-polygon is
    an approximation (vs full line-vs-polygon intersection) chosen to avoid a
    second 160 MB geometry load. Documented in DATA_DECISIONS.md.
    """
    if not cfg.flood_polygons.enabled:
        log.info("flood-polygon positives: disabled (flood_polygons.enabled=false)")
        return pd.DataFrame()

    import geopandas as gpd
    from shapely.geometry import box

    fl = gpd.read_file(resolve(cfg, cfg.paths.flood_extents))
    c = cfg.corridor
    fl = fl[fl.intersects(box(c.min_lon, c.min_lat, c.max_lon, c.max_lat))].copy()
    fl["began"] = pd.to_datetime(fl["Began"], errors="coerce")
    fl = fl[fl.began >= pd.Timestamp(cfg.labels.min_event_date)]
    if fl.empty:
        return pd.DataFrame()

    pts = gpd.GeoDataFrame(
        centroids, geometry=gpd.points_from_xy(centroids.lon, centroids.lat), crs="EPSG:4326"
    )
    hit = gpd.sjoin(pts, fl[["began", "ID", "Severity", "geometry"]], predicate="within")
    rows = []
    for pid, grp in hit.groupby("ID"):
        if len(grp) > cfg.flood_polygons.max_segments_per_polygon:
            grp = grp.sample(cfg.flood_polygons.max_segments_per_polygon, random_state=int(pid) % (2**31))
        for _, h in grp.iterrows():
            span = pd.date_range(h.began.normalize(),
                                 (h.began + pd.Timedelta(days=cfg.flood_polygons.span_days)).normalize(), freq="D")
            conf = cfg.labels.tier_prior["bronze"] * (0.6 if pd.isna(h.Severity) else min(1.0, 0.4 + 0.2 * h.Severity))
            for d in span:
                rows.append({
                    "segment_id": h.segment_id,
                    "date": d,
                    "target": 1,
                    "label_tier": "bronze",
                    "label_confidence": round(float(min(1.0, conf)), 4),
                    "hazard": "flood",
                    "label_source": "dartmouth_flood_poly",
                    "event_id": f"DFO-{int(h.ID)}",
                    "source_lon": np.nan,
                    "source_lat": np.nan,
                    "persist_day": 0,
                    "snap_dist_m": 0.0,
                })
    out = pd.DataFrame(rows)
    log.info("flood-polygon positives: %d segment-day rows", len(out))
    return out


# --------------------------------------------------------------------------- #
# Negatives
# --------------------------------------------------------------------------- #
def build_negatives(pos: pd.DataFrame, centroids: pd.DataFrame, susc: pd.DataFrame,
                    cfg: Config, rng: np.random.Generator) -> pd.DataFrame:
    nc = cfg.negatives
    n_pos = len(pos)
    n_neg = n_pos * nc.ratio

    pos_pts = pos.dropna(subset=["source_lon"]).drop_duplicates(["source_lon", "source_lat"])
    plon = pos_pts.source_lon.to_numpy()
    plat = pos_pts.source_lat.to_numpy()

    def _min_dist_to_event(pool: pd.DataFrame) -> np.ndarray:
        slon, slat = pool.lon.to_numpy(), pool.lat.to_numpy()
        md = np.full(len(pool), np.inf)
        for i in range(0, len(plon), 200):
            d = haversine_m(slon[:, None], slat[:, None], plon[None, i:i + 200], plat[None, i:i + 200])
            md = np.minimum(md, d.min(axis=1))
        return md

    cand = centroids[~centroids.segment_id.isin(pos.segment_id.unique())].copy()
    cand["d_event"] = _min_dist_to_event(cand) if len(plon) else np.inf

    # easy negatives: low-susceptibility plains, far from any hazard
    easy_ids = set(susc[susc.susceptibility_q <= nc.susceptibility_max_quantile].segment_id)
    easy_pool = cand[(cand.d_event > nc.hazard_exclusion_m) & cand.segment_id.isin(easy_ids)]

    # hard negatives: 2-25 km "donut" around events AND susceptibility matched to the
    # positives (same terrain difficulty) — a matched case-control control group.
    cand = cand.merge(susc[["segment_id", "susceptibility_q"]], on="segment_id", how="left")
    pos_susc_lo = float(susc.set_index("segment_id")
                        .reindex(pos.segment_id.unique())["susceptibility_q"].quantile(0.10))
    hard_pool = cand[(cand.d_event > nc.hazard_exclusion_m)
                     & (cand.d_event <= nc.hard_negative_radius_m)
                     & (cand.susceptibility_q >= pos_susc_lo)]
    log.info("negative pools: easy=%d (plains, far)  hard=%d (donut<=%.0fkm & susc>=%.2f)",
             len(easy_pool), len(hard_pool), nc.hard_negative_radius_m / 1000, pos_susc_lo)

    # (3) season-matched date sampling
    pos_years = pd.to_datetime(pos.date).dt.year
    yr_lo, yr_hi = int(pos_years.min()), int(pos_years.max())
    n_monsoon = int(n_neg * nc.monsoon_day_fraction)
    n_uniform = n_neg - n_monsoon

    def sample_dates(n, monsoon_only):
        years = rng.integers(yr_lo, yr_hi + 1, size=n)
        if monsoon_only:
            months = rng.choice(nc.monsoon_months, size=n)
        else:
            months = rng.integers(1, 13, size=n)
        days = rng.integers(1, 29, size=n)
        return pd.to_datetime(dict(year=years, month=months, day=days), errors="coerce")

    dates = pd.concat(
        [pd.Series(sample_dates(n_monsoon, True)), pd.Series(sample_dates(n_uniform, False))],
        ignore_index=True,
    ).sample(frac=1.0, random_state=cfg.seed).reset_index(drop=True)

    n_hard = int(n_neg * nc.hard_negative_fraction) if len(hard_pool) else 0
    n_easy = n_neg - n_hard
    seg_ids = np.concatenate([
        rng.choice(easy_pool.segment_id.to_numpy(), size=n_easy, replace=True),
        rng.choice(hard_pool.segment_id.to_numpy(), size=n_hard, replace=True) if n_hard else np.array([], dtype=object),
    ])
    neg_kind = np.array(["easy"] * n_easy + ["hard"] * n_hard, dtype=object)

    neg = pd.DataFrame(
        {
            "segment_id": seg_ids,
            "date": dates.iloc[: len(seg_ids)].dt.normalize().to_numpy(),
            "target": 0,
            "label_tier": "negative",
            "label_confidence": np.where(neg_kind == "hard", 0.7, 0.9),
            "hazard": "none",
            "label_source": np.where(neg_kind == "hard", "hard_negative_matched", "case_control_negative"),
            "event_id": pd.NA,
            "source_lon": np.nan,
            "source_lat": np.nan,
            "persist_day": 0,
            "snap_dist_m": np.nan,
        }
    ).dropna(subset=["date"]).drop_duplicates(["segment_id", "date"])

    # never let a sampled negative collide with a positive segment-day
    neg = neg.merge(pos[["segment_id", "date"]].drop_duplicates(), on=["segment_id", "date"],
                    how="left", indicator=True)
    neg = neg[neg._merge == "left_only"].drop(columns="_merge")
    log.info("negatives: %d rows (target ratio %d:1)", len(neg), nc.ratio)
    return neg


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def collapse_positives(pos: pd.DataFrame) -> pd.DataFrame:
    """One row per (segment, date): keep the highest-confidence / best tier."""
    tier_rank = {"gold": 0, "silver": 1, "bronze": 2}
    pos = pos.assign(_tr=pos.label_tier.map(tier_rank))
    pos = pos.sort_values(["segment_id", "date", "_tr", "label_confidence"],
                          ascending=[True, True, True, False])
    agg = pos.groupby(["segment_id", "date"], as_index=False).first().drop(columns="_tr")
    return agg


def main(config_path: str | None = None) -> None:
    cfg = load_config(config_path)
    set_seed(cfg.seed)
    rng = np.random.default_rng(cfg.seed)

    src_paths = {k: resolve(cfg, v) for k, v in cfg.paths.items()
                 if k not in ("interim", "processed", "manifests", "reports", "data_root")}
    src_hashes = hash_sources(src_paths)
    check_sources_lock(resolve(cfg, cfg.paths.manifests), src_hashes, log)

    cache = resolve(cfg, cfg.paths.interim) / "segment_centroids.parquet"
    cache.parent.mkdir(parents=True, exist_ok=True)
    centroids = load_segment_centroids(
        resolve(cfg, cfg.paths.roads_gpkg), cfg.corridor.metric_crs, cache_path=cache
    )
    log.info("centroids: %d segments", len(centroids))

    static = pd.read_csv(resolve(cfg, cfg.paths.static_features))
    hydro = pd.read_csv(resolve(cfg, cfg.paths.hydro_features))
    susc = build_susceptibility(static, hydro)
    susc.to_parquet(resolve(cfg, cfg.paths.interim) / "susceptibility_v1.parquet", index=False)

    ev = load_all_events({k: resolve(cfg, cfg.paths[k]) for k in
                          ["glc_bbox", "corridor_landslides", "disruption_events", "road_segment_labels"]})
    ev = filter_events(ev, cfg)
    ev = dedup_events(ev, cfg)
    ev.to_parquet(resolve(cfg, cfg.paths.interim) / "events_dedup_v1.parquet", index=False)

    pos_pt = snap_positives(ev, centroids, cfg, susc)
    pos_fl = flood_polygon_positives(cfg, centroids, rng)
    pos = pd.concat([p for p in (pos_pt, pos_fl) if not p.empty], ignore_index=True)
    pos = pos[(pos.date >= pd.Timestamp(cfg.labels.min_event_date)) &
              (pos.date <= pd.Timestamp(cfg.labels.max_event_date))]
    pos = collapse_positives(pos)
    log.info("collapsed positives: %d unique segment-days", len(pos))

    neg = build_negatives(pos, centroids, susc, cfg, rng)

    labels = pd.concat([pos, neg], ignore_index=True)
    labels["date"] = pd.to_datetime(labels["date"]).dt.normalize()
    labels["sample_weight"] = np.where(labels.target == 1, labels.label_confidence,
                                       labels.label_confidence).clip(0.05, 1.0)
    labels = labels.merge(
        centroids.rename(columns={"lon": "seg_lon", "lat": "seg_lat"}), on="segment_id", how="left"
    )

    out = resolve(cfg, cfg.paths.processed) / "labels_v1.parquet"
    out.parent.mkdir(parents=True, exist_ok=True)
    labels.to_parquet(out, index=False)
    log.info("wrote %s (%d rows)", out, len(labels))

    manifest = {
        "sources": src_hashes,
        "config": dict(cfg),
        "n_events_after_filter": int(len(ev)),
        "n_positive_rows": int((labels.target == 1).sum()),
        "n_negative_rows": int((labels.target == 0).sum()),
        "positive_tier_counts": labels[labels.target == 1].label_tier.value_counts().to_dict(),
        "positive_hazard_counts": labels[labels.target == 1].hazard.value_counts().to_dict(),
        "positive_source_counts": labels[labels.target == 1].label_source.value_counts().to_dict(),
        "positive_year_counts": pd.to_datetime(labels[labels.target == 1].date).dt.year.value_counts().sort_index().to_dict(),
        "n_positive_segments": int(labels[labels.target == 1].segment_id.nunique()),
        "neg_pos_ratio": round(float((labels.target == 0).sum() / max(1, (labels.target == 1).sum())), 2),
        "mean_positive_confidence": round(float(labels[labels.target == 1].label_confidence.mean()), 4),
    }
    write_manifest(resolve(cfg, cfg.paths.manifests), "labels_v1", manifest)
    log.info("label manifest written")


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
