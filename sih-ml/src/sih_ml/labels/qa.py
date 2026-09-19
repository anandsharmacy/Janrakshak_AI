"""Stage 2.1 QA — sanity checks + a human-reviewable positive-label table/map.

Outputs:
  reports/label_qa.md              summary + red flags
  reports/positives_review.csv     every positive event with its source URL (eyeball this)
  reports/label_map.html           leaflet-free scatter (matplotlib) of positives vs corridor
"""
from __future__ import annotations

import pandas as pd

from sih_ml.utils.common import get_logger, load_config, resolve

log = get_logger("label_qa")


def run(config_path: str | None = None) -> dict:
    cfg = load_config(config_path)
    proc = resolve(cfg, cfg.paths.processed)
    rep = resolve(cfg, cfg.paths.reports)
    rep.mkdir(parents=True, exist_ok=True)

    labels = pd.read_parquet(proc / "labels_v1.parquet")
    events = pd.read_parquet(resolve(cfg, cfg.paths.interim) / "events_dedup_v1.parquet")
    pos = labels[labels.target == 1]
    neg = labels[labels.target == 0]

    checks = {}
    # 1. no positive is also a negative
    dup = pd.merge(pos[["segment_id", "date"]], neg[["segment_id", "date"]],
                   on=["segment_id", "date"])
    checks["positive_negative_collision"] = len(dup)
    # 2. temporal gate respected
    checks["positives_before_gate"] = int((pd.to_datetime(pos.date) < pd.Timestamp(cfg.labels.min_event_date)).sum())
    # 3. every positive traceable to an event
    checks["positives_without_event_id"] = int(pos.event_id.isna().sum())
    # 4. dropped-hazard leakage
    hz = pos.hazard.str.lower()
    checks["banned_hazard_in_positives"] = int(hz.apply(
        lambda h: any(k in h for k in cfg.labels.drop_hazards)).sum())
    # 5. neg:pos ratio
    checks["neg_pos_ratio"] = round(len(neg) / max(1, len(pos)), 2)
    # 6. spatial spread of positive segments
    checks["n_positive_segments"] = int(pos.segment_id.nunique())
    checks["n_distinct_events_used"] = int(pos.event_id.nunique())
    # 7. confidence sanity
    checks["positives_conf_gt_1"] = int((pos.label_confidence > 1.0).sum())
    checks["positives_conf_le_0"] = int((pos.label_confidence <= 0).sum())

    red_flags = [k for k, v in checks.items()
                 if k in ("positive_negative_collision", "positives_before_gate",
                          "positives_without_event_id", "banned_hazard_in_positives",
                          "positives_conf_gt_1", "positives_conf_le_0") and v > 0]

    # ---- human review table -------------------------------------------------
    review = events.copy()
    review["n_segment_days_labelled"] = review.event_id.map(
        pos.groupby("event_id").size()).fillna(0).astype(int)
    review = review[["event_id", "source", "date", "lon", "lat", "hazard", "trigger",
                     "location_accuracy_m", "n_merged", "n_segment_days_labelled", "raw_ref"]]
    review.sort_values(["location_accuracy_m", "date"]).to_csv(rep / "positives_review.csv", index=False)

    # ---- map --------------------------------------------------------------
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, ax = plt.subplots(figsize=(9, 8))
        ax.scatter(neg.seg_lon, neg.seg_lat, s=2, c="#cccccc", label="negatives", alpha=.3)
        sc = ax.scatter(pos.seg_lon, pos.seg_lat, s=12, c=pos.label_confidence,
                        cmap="YlOrRd", label="positives", edgecolor="k", linewidth=.2)
        plt.colorbar(sc, label="label_confidence")
        c = cfg.corridor
        ax.set_xlim(c.min_lon, c.max_lon)
        ax.set_ylim(c.min_lat, c.max_lat)
        ax.set_title("Stage 2 labels — corridor disruption")
        ax.legend(loc="lower left")
        fig.savefig(rep / "label_map.png", dpi=110, bbox_inches="tight")
        plt.close(fig)
    except Exception as e:  # matplotlib optional
        log.warning("map skipped: %s", e)

    lines = ["# Label QA — labels_v1", ""]
    lines.append("## Automated checks\n")
    for k, v in checks.items():
        mark = " ⚠️" if k in red_flags else ""
        lines.append(f"- {k}: **{v}**{mark}")
    lines += ["", f"## Red flags: {red_flags or 'none'}", "",
              "## Manual step (required before modelling)",
              "Open `positives_review.csv`, sort by `location_accuracy_m`, and eyeball the "
              "20 coarsest-located events against their `raw_ref` URL. Mark false positives "
              "in a `verdict` column and re-run with an exclusion list.",
              "", "See `label_map.png` for the spatial distribution (colour = confidence)."]
    (rep / "label_qa.md").write_text("\n".join(lines))
    log.info("QA checks: %s", checks)
    if red_flags:
        log.warning("RED FLAGS: %s", red_flags)
    return {"checks": checks, "red_flags": red_flags}


if __name__ == "__main__":
    import sys

    run(sys.argv[1] if len(sys.argv) > 1 else None)
