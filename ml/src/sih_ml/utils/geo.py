"""Geospatial helpers: centroids, nearest-neighbour joins, spatial blocks."""
from __future__ import annotations

import numpy as np
import pandas as pd

EARTH_R_M = 6_371_000.0


def haversine_m(lon1, lat1, lon2, lat2):
    """Vectorised great-circle distance in metres."""
    lon1, lat1, lon2, lat2 = map(np.radians, (lon1, lat1, lon2, lat2))
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = np.sin(dlat / 2) ** 2 + np.cos(lat1) * np.cos(lat2) * np.sin(dlon / 2) ** 2
    return 2 * EARTH_R_M * np.arcsin(np.sqrt(a))


def load_segment_centroids(roads_gpkg, metric_crs="EPSG:32645", cache_path=None):
    """Return DataFrame [segment_id, lon, lat] of segment centroids.

    Cached to parquet because reading the 160 MB gpkg takes ~30 s.
    """
    from pathlib import Path

    if cache_path is not None:
        cp = Path(cache_path)
        stamp = cp.with_suffix(".src_mtime")
        src_mtime = str(Path(roads_gpkg).stat().st_mtime)
        if cp.exists() and stamp.exists() and stamp.read_text() == src_mtime:
            return pd.read_parquet(cp)

    import geopandas as gpd

    gdf = gpd.read_file(roads_gpkg, columns=["segment_id"])
    # centroid in a metric CRS then back to 4326 for a correct centroid
    cent = gdf.to_crs(metric_crs).geometry.centroid.to_crs("EPSG:4326")
    out = pd.DataFrame(
        {"segment_id": gdf["segment_id"].to_numpy(), "lon": cent.x.to_numpy(), "lat": cent.y.to_numpy()}
    )
    if cache_path is not None:
        out.to_parquet(cache_path, index=False)
        Path(cache_path).with_suffix(".src_mtime").write_text(str(Path(roads_gpkg).stat().st_mtime))
    return out


def segments_within(centroids: pd.DataFrame, lon: float, lat: float, radius_m: float,
                    max_n: int | None = None) -> pd.DataFrame:
    """All segments whose centroid is within radius_m of (lon, lat).

    Returns [segment_id, dist_m] sorted ascending. A coarse bbox pre-filter keeps
    this cheap for 300k segments.
    """
    deg = radius_m / 111_320.0 * 1.6  # generous bbox pad
    m = (
        (centroids.lon.between(lon - deg, lon + deg))
        & (centroids.lat.between(lat - deg, lat + deg))
    )
    cand = centroids.loc[m].copy()
    if cand.empty:
        return cand.assign(dist_m=pd.Series(dtype=float))
    cand["dist_m"] = haversine_m(cand.lon.to_numpy(), cand.lat.to_numpy(), lon, lat)
    cand = cand.loc[cand.dist_m <= radius_m].sort_values("dist_m")
    if max_n is not None:
        cand = cand.head(max_n)
    return cand[["segment_id", "dist_m"]]


def nearest_row(centroids: pd.DataFrame, lon: float, lat: float) -> tuple[str, float]:
    d = haversine_m(centroids.lon.to_numpy(), centroids.lat.to_numpy(), lon, lat)
    i = int(np.argmin(d))
    return centroids.segment_id.iloc[i], float(d[i])


def assign_spatial_block(lon, lat, block_deg: float, origin_lon: float, origin_lat: float) -> pd.Series:
    """Grid cell id 'BLK_{col}_{row}' for each point."""
    col = np.floor((np.asarray(lon) - origin_lon) / block_deg).astype(int)
    row = np.floor((np.asarray(lat) - origin_lat) / block_deg).astype(int)
    return pd.Series([f"BLK_{c:03d}_{r:03d}" for c, r in zip(col, row)])


def nearest_cell_map(centroids: pd.DataFrame, cells: pd.DataFrame) -> pd.DataFrame:
    """Map each segment centroid to its nearest rainfall grid cell.

    cells: DataFrame [cell_id, latitude, longitude]. Returns [segment_id, cell_id, cell_dist_m].
    """
    cell_lon = cells.longitude.to_numpy()
    cell_lat = cells.latitude.to_numpy()
    cell_id = cells.cell_id.to_numpy()
    seg_lon = centroids.lon.to_numpy()[:, None]
    seg_lat = centroids.lat.to_numpy()[:, None]
    # small grids (~132 cells) -> full distance matrix is fine
    d = haversine_m(seg_lon, seg_lat, cell_lon[None, :], cell_lat[None, :])
    j = np.argmin(d, axis=1)
    return pd.DataFrame(
        {
            "segment_id": centroids.segment_id.to_numpy(),
            "cell_id": cell_id[j],
            "cell_dist_m": d[np.arange(len(j)), j],
        }
    )
