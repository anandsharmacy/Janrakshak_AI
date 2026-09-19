"""Stage 2.5 — build evaluation splits. NEVER random k-fold.

Output: data/processed/folds_v1.parquet + manifests/folds_v1.json + reports/split_diagnostics.md

Columns added per panel row:
    spatial_block_id            grid cell (~25 km)
    event_cluster_id            DBSCAN cluster of positives in space+time (for LOECO)
    spatial_fold                0..K-1  (GroupKFold on spatial_block_id)
    spatial_role_f{k}           train / val / buffer   for outer fold k
    temporal_split              train / val / test     (out-of-time)
    final_test                  bool   (locked hold-out: WHOLE held-out block-components only)
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.cluster import DBSCAN
from sklearn.model_selection import GroupKFold

from sih_ml.utils.common import get_logger, load_config, resolve, set_seed, write_manifest
from sih_ml.utils.geo import assign_spatial_block, haversine_m

log = get_logger("splits")


def _spatial_blocks(df: pd.DataFrame, cfg) -> pd.Series:
    return assign_spatial_block(
        df["seg_lon"].to_numpy(), df["seg_lat"].to_numpy(),
        cfg.split.block_deg, cfg.corridor.min_lon, cfg.corridor.min_lat,
    ).to_numpy()


def _event_clusters(df: pd.DataFrame, cfg) -> pd.Series:
    """DBSCAN on positives over (lon, lat, time-bucket); negatives get -1."""
    pos = df[df.target == 1].copy()
    if pos.empty:
        return pd.Series(-1, index=df.index)
    t = (pd.to_datetime(pos.date) - pd.Timestamp("2005-01-01")).dt.days.to_numpy()
    tb = t / cfg.split.cluster_time_bucket_days * cfg.split.cluster_eps_deg
    X = np.column_stack([pos.seg_lon.to_numpy(), pos.seg_lat.to_numpy(), tb])
    lab = DBSCAN(eps=cfg.split.cluster_eps_deg, min_samples=cfg.split.cluster_min_samples).fit_predict(X)
    # give singleton/noise points their own ids too
    nxt = lab.max() + 1
    lab = lab.copy()
    for i in np.where(lab == -1)[0]:
        lab[i] = nxt
        nxt += 1
    out = pd.Series(-1, index=df.index)
    out.loc[pos.index] = lab
    return out


def _spatial_folds(df: pd.DataFrame, cfg) -> pd.DataFrame:
    """GroupKFold on spatial_block_id, stratified-ish so each val fold holds >=1 positive.
    Adds spatial_fold and, per fold k, a train/val/buffer role column."""
    blocks = df["spatial_block_id"].to_numpy()
    uniq = pd.Series(blocks).drop_duplicates().to_numpy()
    # order blocks by positive count so folds are balanced by positives
    pos_by_block = df[df.target == 1].groupby("spatial_block_id").size()
    order = sorted(uniq, key=lambda b: (-pos_by_block.get(b, 0), b))
    k = cfg.split.n_spatial_folds
    block_fold = {b: (i % k) for i, b in enumerate(order)}
    df = df.copy()
    df["spatial_fold"] = pd.Series(blocks).map(block_fold).to_numpy()

    # buffer: training rows whose centroid is within fold_buffer_m of ANY val-fold segment
    buf = cfg.split.fold_buffer_m
    for f in range(k):
        val_mask = df.spatial_fold.to_numpy() == f
        role = np.where(val_mask, "val", "train").astype(object)
        vlon = df.loc[val_mask, "seg_lon"].to_numpy()
        vlat = df.loc[val_mask, "seg_lat"].to_numpy()
        if len(vlon):
            tr_idx = np.where(~val_mask)[0]
            tlon = df["seg_lon"].to_numpy()[tr_idx]
            tlat = df["seg_lat"].to_numpy()[tr_idx]
            hit = np.zeros(len(tr_idx), dtype=bool)
            for i in range(0, len(vlon), 300):
                d = haversine_m(tlon[:, None], tlat[:, None],
                                vlon[None, i:i + 300], vlat[None, i:i + 300])
                hit |= d.min(axis=1) < buf
            role[tr_idx[hit]] = "buffer"
        df[f"spatial_role_f{f}"] = role
    return df


def _mark_test_rows(df: pd.DataFrame, cfg) -> pd.DataFrame:
    """Held-out final-test rows get no CV fold."""
    df["spatial_fold"] = -1
    for f in range(cfg.split.n_spatial_folds):
        df[f"spatial_role_f{f}"] = "test"
    return df


def _temporal_split(df: pd.DataFrame, cfg) -> pd.Series:
    d = pd.to_datetime(df.split_date)
    out = np.where(d <= pd.Timestamp(cfg.split.temporal_train_end), "train",
          np.where(d <= pd.Timestamp(cfg.split.temporal_val_end), "val", "test"))
    return pd.Series(out, index=df.index)


def _block_components(df: pd.DataFrame) -> dict:
    """Union-find over spatial blocks, merging any two that share a segment or an event.

    Why this is needed. A segment lives in exactly one geographic block, but
    `main()` re-pins every POSITIVE row to its event's *modal* block so an event
    never straddles a split. That re-pinning can therefore move some of a segment's
    rows into a different block than its other rows (measured: 4 of 61,872 segments).
    If one of those blocks were held out and the other were not, that segment would
    sit on both sides of the dev/test boundary — and since its static terrain columns
    are an exact per-segment fingerprint, the model could recognise it at test time
    with no weather skill at all.

    Holding out whole *components* instead of whole blocks makes that impossible by
    construction. Measured cost on the current data: 114 blocks collapse to 113
    components (a single 2-block merge), so this is essentially free insurance
    against a failure that one data refresh could otherwise trigger.
    """
    parent: dict = {}

    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    for b in df.spatial_block_id.unique():
        find(b)
    for _, blocks in df.groupby("segment_id").spatial_block_id.unique().items():
        for b in blocks[1:]:
            union(blocks[0], b)
    pos = df[df.target == 1]
    if len(pos):
        for _, blocks in pos.groupby("event_id").spatial_block_id.unique().items():
            for b in blocks[1:]:
                union(blocks[0], b)
    return {b: find(b) for b in df.spatial_block_id.unique()}


def _select_held_blocks(df: pd.DataFrame, cfg, rng) -> list[str]:
    """Choose the locked test set as a union of WHOLE block-components.

    `cfg.split.hold_gold_blocks` controls whether the component containing the
    verified (gold) labels is force-included. It defaults to **false**, and that is a
    deliberate trade documented in FINAL_MODEL.md: on this data the gold-bearing
    component carries 37.4% of all positives, so forcing it into the test set would
    cost more than a third of the training positives and leave the test dominated by
    two adjacent blocks — swapping one composition confound for another to retain 3
    rows that are statistically inert at n=3. Setting it true is supported for a
    future dataset where verified labels are plentiful enough to matter.
    """
    comp_of = _block_components(df)
    pos_blocks = df[df.target == 1].spatial_block_id.value_counts()
    if not len(pos_blocks):
        return []

    # Draw at the BLOCK level with the identical RNG call the original used, then
    # EXPAND each drawn block to its whole component. Keeping the draw itself
    # unchanged matters: re-sampling the locked test region after discovering that
    # the old one failed would be choosing a test set post-hoc, which is exactly the
    # cherry-picking this project's discipline forbids. Expansion only ever adds the
    # blocks that are structurally inseparable from one already drawn.
    n_hold = max(1, int(round(cfg.split.test_block_frac * len(pos_blocks))))
    drawn = [pos_blocks.index[i] for i in rng.choice(len(pos_blocks), size=n_hold,
                                                     replace=False)]
    held_comps = list(dict.fromkeys(comp_of[b] for b in drawn))

    if bool(cfg.split.get("hold_gold_blocks", False)):
        for b in df.loc[df.label_tier == "gold", "spatial_block_id"].unique():
            if comp_of[b] not in held_comps:
                held_comps.append(comp_of[b])

    held = sorted(b for b, c in comp_of.items() if c in held_comps)
    added = sorted(set(held) - set(drawn))
    if added:
        log.info("component expansion pulled in %d extra block(s): %s", len(added), added)
    return held


def _final_test(df: pd.DataFrame, held_blocks: list[str]) -> pd.Series:
    """Locked test = whole held-out block-components. Nothing else.

    HISTORY — this line caused the project's only real leak. It used to read:

        df.spatial_block_id.isin(held_blocks) | (df.label_tier == "gold")

    The `| gold` clause pulled every verified row into the test set *regardless of
    its block*. All 3 gold rows sit in BLK_005_006, which was NOT among the held
    blocks, so 3 rows were lifted out of a 4,424-row block whose other 4,421 rows —
    including 15 positive rows of the very same segment, SEG291652, across 5
    distinct events — stayed in training. The spatial partition was working
    correctly; this OR-clause overrode it. Stage 8 then measured the consequence:
    deleting rainfall entirely left those rows' percentile rank essentially
    unchanged (99.29 -> 99.11), i.e. their top-1% position was segment-identity
    memorisation rather than rainfall skill.

    A membership rule for the locked split must be a function of the BLOCK ALONE.
    Any predicate on a row attribute (tier, source, date, hazard) can cut across
    blocks and silently break the partition.
    """
    return df.spatial_block_id.isin(held_blocks)


def assert_no_split_leakage(df: pd.DataFrame) -> dict:
    """Hard gate: the dev/test partition must share no segment, event or block.

    Runs on EVERY split rebuild and raises. The previous leak survived because the
    audit was a one-off analysis performed three stages later; a gate that runs at
    build time cannot be forgotten.
    """
    dev, te = df[~df.final_test], df[df.final_test]
    shared_seg = set(dev.segment_id) & set(te.segment_id)
    pos_ev = lambda d: set(d.loc[d.target == 1, "event_id"].dropna().astype(str)) - {"nan", "None"}
    shared_ev = pos_ev(dev) & pos_ev(te)
    shared_blk = set(dev.spatial_block_id) & set(te.spatial_block_id)
    problems = []
    if shared_seg:
        problems.append(f"{len(shared_seg)} segment_id(s) in both dev and test: "
                        f"{sorted(shared_seg)[:5]}")
    if shared_ev:
        problems.append(f"{len(shared_ev)} positive event_id(s) in both: {sorted(shared_ev)[:5]}")
    if shared_blk:
        problems.append(f"{len(shared_blk)} spatial_block(s) in both: {sorted(shared_blk)[:5]}")
    if problems:
        raise ValueError("SPLIT LEAKAGE GATE FAILED — " + " | ".join(problems))
    return {"shared_segments": 0, "shared_positive_events": 0, "shared_blocks": 0,
            "n_dev_rows": int(len(dev)), "n_test_rows": int(len(te)),
            "n_test_segments": int(te.segment_id.nunique())}


def main(config_path: str | None = None) -> None:
    cfg = load_config(config_path)
    set_seed(cfg.seed)
    rng = np.random.default_rng(cfg.seed)

    panel = pd.read_parquet(resolve(cfg, cfg.paths.processed) / "panel_v1.parquet")
    df = panel[["segment_id", "date", "target", "label_tier", "seg_lon", "seg_lat", "event_id"]].copy()

    df["spatial_block_id"] = _spatial_blocks(df, cfg)

    # An event snaps to many segments that can straddle a block/fold/year boundary.
    # Pin every positive row of an event to that event's MODAL block and EARLIEST
    # date so the event is never split across train/val/test. Negatives keep their
    # own block. This is the group-integrity guarantee the tests enforce.
    pos_m = df.target == 1
    ev_block = df.loc[pos_m].groupby("event_id")["spatial_block_id"].agg(lambda s: s.mode().iat[0])
    ev_date = df.loc[pos_m].groupby("event_id")["date"].min()
    df.loc[pos_m, "spatial_block_id"] = df.loc[pos_m, "event_id"].map(ev_block)
    df["split_date"] = df["date"]
    df.loc[pos_m, "split_date"] = df.loc[pos_m, "event_id"].map(ev_date)

    df["event_cluster_id"] = _event_clusters(df, cfg)

    # lock aside whole block-COMPONENTS before building CV folds, so the final test
    # is never seen by any fold and cannot share a segment or event with dev
    held_blocks = _select_held_blocks(df, cfg, rng)
    df["final_test"] = _final_test(df, held_blocks)
    leak_gate = assert_no_split_leakage(df)
    log.info("leakage gate passed: %s", leak_gate)

    df = _spatial_folds(df[~df.final_test].copy(), cfg).pipe(
        lambda d: pd.concat([d, _mark_test_rows(df[df.final_test].copy(), cfg)], axis=0)
    ).sort_index()
    df["temporal_split"] = _temporal_split(df, cfg)

    keep = ["segment_id", "date", "split_date", "spatial_block_id", "event_cluster_id", "spatial_fold",
            *[f"spatial_role_f{f}" for f in range(cfg.split.n_spatial_folds)],
            "temporal_split", "final_test"]
    folds = df[keep]
    out = resolve(cfg, cfg.paths.processed) / "folds_v1.parquet"
    folds.to_parquet(out, index=False)
    log.info("wrote %s shape=%s", out, folds.shape)

    # ---- diagnostics -----------------------------------------------------
    pos = df[df.target == 1]
    diag = {
        "n_spatial_blocks": int(df.spatial_block_id.nunique()),
        "n_blocks_with_positive": int(pos.spatial_block_id.nunique()),
        "n_event_clusters": int(pos.event_cluster_id.nunique()),
        "held_out_test_blocks": held_blocks,
        "leakage_gate": leak_gate,
        "hold_gold_blocks": bool(cfg.split.get("hold_gold_blocks", False)),
        "gold_in_final_test": int(((df.label_tier == "gold") & df.final_test).sum()),
        "positives_per_spatial_fold": pos.groupby("spatial_fold").size().to_dict(),
        "rows_per_spatial_fold": df.groupby("spatial_fold").size().to_dict(),
        "temporal_split_positives": pos.groupby("temporal_split").size().to_dict(),
        "temporal_split_rows": df.groupby("temporal_split").size().to_dict(),
        "final_test_positives": int(df[df.final_test].pipe(lambda x: (x.target == 1).sum())
                                    if "target" in df else 0),
        "final_test_rows": int(df.final_test.sum()),
        "buffer_rows_per_fold": {f: int((df[f"spatial_role_f{f}"] == "buffer").sum())
                                 for f in range(cfg.split.n_spatial_folds)},
    }
    write_manifest(resolve(cfg, cfg.paths.manifests), "folds_v1", {"config_split": dict(cfg.split), **diag})

    lines = ["# Split diagnostics (folds_v1)", ""]
    for k, v in diag.items():
        lines.append(f"- **{k}**: {v}")
    lines += ["", "## Leakage rules enforced", "",
              "- Outer folds grouped by `spatial_block_id` (GroupKFold-style): a block is never split.",
              f"- Training rows within {cfg.split.fold_buffer_m} m of a validation block are marked `buffer` and must be dropped from that fold's training set.",
              "- `event_cluster_id` groups positives in space+time for Leave-One-Event-Cluster-Out CV.",
              "- Temporal split is a true out-of-time hold-out (train ≤ {}, val ≤ {}, test after).".format(
                  cfg.split.temporal_train_end, cfg.split.temporal_val_end),
              "- `final_test` rows are locked: never use for any fitting, HPO, or threshold choice."]
    (resolve(cfg, cfg.paths.reports) / "split_diagnostics.md").write_text("\n".join(lines))
    log.info("diagnostics: %s", diag)


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
