"""Stage 8 §4 — generalization, leakage and dataset-bias audits on the FINAL model.

The leakage question is not "did we write the splits correctly" — Stage 2 tests that
already. It is the sharper one: **for this specific trained model, is there any path
by which a test row's answer was available at training time?** Three paths are
checked, in increasing subtlety:

  1. the same (segment, date) row appearing on both sides            — trivial
  2. the same `event_id` appearing on both sides                     — Stage 2's pinning
  3. the same `segment_id` appearing on both sides                   — the dangerous one

(3) is dangerous because a segment's static columns (slope, elevation, lithology,
soil, road class) are effectively a unique per-segment fingerprint. A model that saw
a segment labelled positive during training can recognise it at test time from
terrain alone, with no rainfall skill whatsoever. Stage 3 already lost a LOECO
experiment to exactly this mechanism, and Stage 7 found that blurring those columns
with noise was the single largest accuracy gain in the stage — both are symptoms of
the same underlying property of this dataset.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score

from sih_ml.models.dataset import Data
from sih_ml.utils.common import get_logger

log = get_logger("stage8.audit")


def leakage_audit(data: Data) -> dict:
    """Enumerate every overlap path between the dev (training) rows and the locked
    test rows, and identify exactly which test rows are affected."""
    te = data.final_test_index()
    dev = np.where(data.dev_mask())[0]
    P = data.panel

    seg_d = P["segment_id"].to_numpy()[dev]
    seg_t = P["segment_id"].to_numpy()[te]
    dt_d = P["date"].to_numpy()[dev]
    dt_t = P["date"].to_numpy()[te]
    ev_d = P["event_id"].astype(str).to_numpy()[dev]
    ev_t = P["event_id"].astype(str).to_numpy()[te]
    blk_d = P["spatial_block_id"].to_numpy()[dev]
    blk_t = P["spatial_block_id"].to_numpy()[te]
    y_d, y_t = data.y[dev], data.y[te]

    row_overlap = len(set(zip(seg_d, dt_d)) & set(zip(seg_t, dt_t)))
    pos_events_d = set(ev_d[y_d == 1]) - {"nan", "None"}
    pos_events_t = set(ev_t[y_t == 1]) - {"nan", "None"}
    ev_overlap = pos_events_d & pos_events_t

    shared_segs = set(seg_d) & set(seg_t)
    shared_blocks = set(blk_d) & set(blk_t)

    # which test rows sit on a segment the model trained on, and how the model saw it
    affected = []
    for s in sorted(shared_segs):
        d_rows = dev[seg_d == s]
        t_rows = te[seg_t == s]
        affected.append({
            "segment_id": s,
            "train_rows": int(len(d_rows)),
            "train_positive_rows": int(data.y[d_rows].sum()),
            "train_distinct_events": int(len(set(P["event_id"].astype(str).to_numpy()[d_rows]) - {"nan", "None"})),
            "test_rows": int(len(t_rows)),
            "test_positive_rows": int(data.y[t_rows].sum()),
            "test_tiers": sorted(set(P["label_tier"].to_numpy()[t_rows])),
            "min_days_between": int(np.min(np.abs(
                (P["date"].to_numpy()[t_rows][:, None]
                 - P["date"].to_numpy()[d_rows][None, :]).astype("timedelta64[D]").astype(int)))),
        })

    return {
        "n_test_rows": int(len(te)), "n_dev_rows": int(len(dev)),
        "exact_row_overlap": row_overlap,
        "shared_positive_event_ids": sorted(ev_overlap),
        "n_shared_segments": len(shared_segs),
        "n_test_segments": int(pd.unique(seg_t).size),
        "shared_segment_detail": affected,
        "n_shared_blocks": len(shared_blocks),
        "shared_blocks": sorted(shared_blocks),
        "n_test_blocks": int(pd.unique(blk_t).size),
        "test_blocks": sorted(pd.unique(blk_t).tolist()),
        "test_rows_on_shared_segments": int(sum(a["test_rows"] for a in affected)),
    }


def generalization_table(data: Data, model, tr_idx: np.ndarray, es_idx: np.ndarray,
                         oof_path, te_idx: np.ndarray, te_pred: np.ndarray) -> pd.DataFrame:
    """Train / early-stopping / dev-OOF / test on one axis.

    The train row is the overfitting check. Stage 5 measured the old configuration at
    in-sample AP 0.9999 against 0.29 held out — near-total memorisation. If Stage 7's
    regularisation did what it claims, this number must have fallen substantially.
    """
    rows = []

    def add(name, y, p, note):
        if len(y) == 0 or y.sum() == 0:
            return
        rows.append({"split": name, "n": int(len(y)), "n_pos": int(y.sum()),
                     "base_rate": float(y.mean()),
                     "AP": float(average_precision_score(y, p)),
                     "AP_over_base": float(average_precision_score(y, p) / y.mean()),
                     "roc_auc": float(roc_auc_score(y, p)) if 0 < y.sum() < len(y) else np.nan,
                     "note": note})

    add("train (in-sample)", data.y[tr_idx], model.predict(data.X(tr_idx)),
        "rows the final model fitted on")
    add("early-stopping", data.y[es_idx], model.predict(data.X(es_idx)),
        "event-grouped holdout that chose the round count")
    if oof_path is not None and oof_path.exists():
        oof = pd.read_parquet(oof_path)
        add("dev spatial-CV OOF", oof["target"].to_numpy(int), oof["score"].to_numpy(float),
            "each row scored by a model that never saw it")
    add("LOCKED TEST", data.y[te_idx], te_pred, "opened once, under pre-registration")
    return pd.DataFrame(rows)


def label_source_shift(data: Data) -> pd.DataFrame:
    """Composition of positives by label source, dev vs locked test, with the mean
    rainfall each source carries.

    This exists because the headline test result cannot be interpreted without it.
    `final_test` was defined in Stage 2 as a set of spatial blocks **plus every gold
    label**, with no constraint on label-source mix — so the split is free to differ
    from dev in *what kind of positive it contains*, not just where. If the test
    positives come disproportionately from news-derived sources whose dates are
    unreliable and whose rainfall is near zero, then a drop in test performance is
    partly a label-quality shift and only partly a generalization failure. Those two
    are not the same finding and should not be reported as one.
    """
    P = data.panel
    te = data.final_test_index()
    dev = np.where(data.dev_mask())[0]
    r7 = np.nan_to_num(P["rain_7d_mm"].to_numpy(float))
    y = data.y

    rows = []
    for name, idx in [("dev", dev), ("locked test", te)]:
        pos = idx[y[idx] == 1]
        src = P["label_source"].to_numpy()[pos]
        for s in pd.unique(src):
            m = src == s
            rows.append({"split": name, "label_source": s, "n_positives": int(m.sum()),
                         "share_of_positives": float(m.mean()),
                         "mean_rain_7d_mm": float(r7[pos][m].mean())})
    return pd.DataFrame(rows)


def rainfall_signal_check(data: Data) -> pd.DataFrame:
    """Is rainfall, on its own, able to separate positives from negatives?

    No model involved — just each rainfall feature used directly as a ranking score.
    ROC-AUC is used because it is base-rate independent and the two splits have very
    different base rates. A value at or below 0.5 on a split means the feature that
    the entire problem framing rests on carries no usable signal there.
    """
    from sklearn.metrics import roc_auc_score
    P = data.panel
    te = data.final_test_index()
    dev = np.where(data.dev_mask())[0]
    y = data.y
    feats = ["rain_1d_mm", "rain_3d_mm", "rain_7d_mm", "rain_15d_mm", "rain_30d_mm",
             "api_mm", "id_ratio_3d"]
    rows = []
    for c in feats:
        if c not in P:
            continue
        v = np.nan_to_num(P[c].to_numpy(float))
        r = {"feature": c}
        for name, idx in [("dev", dev), ("test", te)]:
            yy, vv = y[idx], v[idx]
            r[f"{name}_roc"] = (float(roc_auc_score(yy, vv))
                                if 0 < yy.sum() < len(yy) else np.nan)
            r[f"{name}_mean_pos"] = float(vv[yy == 1].mean())
            r[f"{name}_mean_neg"] = float(vv[yy == 0].mean())
        rows.append(r)
    return pd.DataFrame(rows)


def bias_analysis(data: Data, te_idx: np.ndarray, pred: np.ndarray) -> pd.DataFrame:
    """Performance across the groups a deployment would be challenged on.

    `AP_over_base` is the column to read, not AP: these groups have wildly different
    base rates (a `trunk` road subset is ~46% positive, the flattest terrain ~0.5%),
    and average precision scales with the base rate, so raw AP is not comparable
    across rows here.
    """
    P = data.panel.iloc[te_idx]
    y = data.y[te_idx]
    rows = []

    def add(kind, label, m):
        m = np.asarray(m, bool)
        if m.sum() < 30 or y[m].sum() < 3:
            return
        base = float(y[m].mean())
        ap = float(average_precision_score(y[m], pred[m]))
        rows.append({"group_type": kind, "group": str(label), "n": int(m.sum()),
                     "n_pos": int(y[m].sum()), "base_rate": base, "AP": ap,
                     "AP_over_base": ap / base if base else np.nan,
                     "roc_auc": (float(roc_auc_score(y[m], pred[m]))
                                 if 0 < y[m].sum() < m.sum() else np.nan),
                     "mean_score": float(pred[m].mean())})

    add("overall", "all", np.ones(len(y), bool))
    for t in ["gold", "silver", "bronze"]:
        add("label_tier", t, (P["label_tier"] == t).to_numpy() | (y == 0))
    for h in pd.unique(P["hazard"].dropna()):
        add("hazard", h, (P["hazard"] == h).to_numpy() | (y == 0))
    for b in sorted(pd.unique(P["spatial_block_id"])):
        add("spatial_block", b, (P["spatial_block_id"] == b).to_numpy())
    s = np.nan_to_num(P["slope_mean_deg"].to_numpy(float), nan=0.0)
    for lo, hi in [(0, 2.5), (2.5, 10), (10, 20), (20, 90)]:
        add("slope_deg", f"[{lo:g}, {hi:g})", (s >= lo) & (s < hi))
    add("season", "monsoon", P["is_monsoon"].to_numpy().astype(bool))
    add("season", "dry", ~P["is_monsoon"].to_numpy().astype(bool))
    for hw in P["highway"].value_counts().head(6).index:
        add("highway", hw, (P["highway"] == hw).to_numpy())
    add("soil", "soil NODATA", P["soil_is_missing"].to_numpy().astype(bool))
    add("soil", "soil present", ~P["soil_is_missing"].to_numpy().astype(bool))
    yr = pd.to_datetime(P["date"]).dt.year.to_numpy()
    for lo, hi in [(2007, 2013), (2013, 2019), (2019, 2027)]:
        add("period", f"{lo}-{hi - 1}", (yr >= lo) & (yr < hi))
    return pd.DataFrame(rows)
