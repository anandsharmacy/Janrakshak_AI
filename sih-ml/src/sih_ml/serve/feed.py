"""Rainfall feed ingestion — append new days to the feature store.

    python -m sih_ml.serve.feed --csv new_days.csv      # long format: date,cell_id,precip_mm

The model was trained on CHIRPS final, which is published weeks after the fact. An
operational deployment must ingest a near-real-time product instead (CHIRPS-prelim,
GPM IMERG-Early, or IMD gridded), resampled to the same 0.05-degree cells. That source
swap is a distribution shift the model has not seen: the per-month drift check in
batch.py's run.json exists to catch it, and the probability caveat in the bundle
policy applies with extra force until a calibrator has been refitted on local,
operational-feed history.

Checks before anything is written: every cell present for every new day, no gaps
between the store's last day and the new ones, values finite and within
[0, MAX_DAILY_MM]. The write is atomic (temp file + rename).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.serve.validate import MAX_DAILY_MM


def validate_new_days(new: pd.DataFrame, cells: list[str], last_day: pd.Timestamp) -> pd.DataFrame:
    need = {"date", "cell_id", "precip_mm"}
    if not need <= set(new.columns):
        raise ValueError(f"feed CSV needs columns {sorted(need)}")
    new = new.copy()
    new["date"] = pd.to_datetime(new["date"]).dt.normalize()
    new["cell_id"] = new["cell_id"].astype(str)
    wide = new.pivot_table(index="date", columns="cell_id", values="precip_mm", aggfunc="mean")
    missing = sorted(set(cells) - set(wide.columns))
    if missing:
        raise ValueError(f"{len(missing)} cells missing from the feed, e.g. {missing[:3]}")
    wide = wide[cells].sort_index()
    if wide.isna().any().any():
        raise ValueError("feed has cell-days without a value — refusing to impute rainfall")
    v = wide.to_numpy(float)
    if not np.isfinite(v).all() or (v < 0).any() or (v > MAX_DAILY_MM).any():
        raise ValueError(f"feed values must be finite and within [0, {MAX_DAILY_MM:g}] mm/day")
    days = wide.index
    new_days = days[days > last_day]
    if len(new_days) and new_days[0] != last_day + pd.Timedelta(days=1):
        raise ValueError(f"gap in feed: store ends {last_day.date()}, feed resumes "
                         f"{new_days[0].date()}")
    if len(new_days) and (pd.Series(new_days).diff().dropna() != pd.Timedelta(days=1)).any():
        raise ValueError("feed days are not contiguous")
    return wide


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--csv", required=True)
    ap.add_argument("--store", default=os.environ.get("SIH_STORE", "deploy/featurestore"))
    a = ap.parse_args(argv)
    store = Path(a.store)
    man = json.loads((store / "manifest.json").read_text())
    rain = pd.read_parquet(store / "rainfall.parquet")
    rain.index = pd.DatetimeIndex(rain.index)
    wide = validate_new_days(pd.read_csv(a.csv), man["cell_ids"], rain.index.max())
    merged = pd.concat([rain[~rain.index.isin(wide.index)], wide]).sort_index().asfreq("D")
    tmp = store / ".rainfall.parquet.tmp"
    merged.to_parquet(tmp)
    os.replace(tmp, store / "rainfall.parquet")
    man["rain_last"] = str(merged.index.max().date())
    (store / "manifest.json").write_text(json.dumps(man, indent=1))
    print(json.dumps({"appended_days": int((wide.index > rain.index.max()).sum()),
                      "revised_days": int(wide.index.isin(rain.index).sum()),
                      "rain_last": man["rain_last"]}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
