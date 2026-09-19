# Label QA — labels_v1

## Automated checks

- positive_negative_collision: **0**
- positives_before_gate: **0**
- positives_without_event_id: **0**
- banned_hazard_in_positives: **0**
- neg_pos_ratio: **10.0**
- n_positive_segments: **2011**
- n_distinct_events_used: **173**
- positives_conf_gt_1: **0**
- positives_conf_le_0: **0**

## Red flags: none

## Manual step (required before modelling)
Open `positives_review.csv`, sort by `location_accuracy_m`, and eyeball the 20 coarsest-located events against their `raw_ref` URL. Mark false positives in a `verdict` column and re-run with an exclusion list.

See `label_map.png` for the spatial distribution (colour = confidence).