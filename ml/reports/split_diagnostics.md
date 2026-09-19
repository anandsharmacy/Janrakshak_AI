# Split diagnostics (folds_v1)

- **n_spatial_blocks**: 114
- **n_blocks_with_positive**: 31
- **n_event_clusters**: 115
- **held_out_test_blocks**: ['BLK_004_006', 'BLK_004_007', 'BLK_005_004', 'BLK_006_008', 'BLK_009_005']
- **leakage_gate**: {'shared_segments': 0, 'shared_positive_events': 0, 'shared_blocks': 0, 'n_dev_rows': 94972, 'n_test_rows': 8274, 'n_test_segments': 4391}
- **hold_gold_blocks**: False
- **gold_in_final_test**: 0
- **positives_per_spatial_fold**: {-1: 1341, 0: 2571, 1: 2286, 2: 1449, 3: 891, 4: 849}
- **rows_per_spatial_fold**: {-1: 8274, 0: 21634, 1: 17549, 2: 20629, 3: 20266, 4: 14894}
- **temporal_split_positives**: {'test': 1080, 'train': 6705, 'val': 1602}
- **temporal_split_rows**: {'test': 38686, 'train': 48812, 'val': 15748}
- **final_test_positives**: 1341
- **final_test_rows**: 8274
- **buffer_rows_per_fold**: {0: 8234, 1: 10402, 2: 11011, 3: 9028, 4: 7769}

## Leakage rules enforced

- Outer folds grouped by `spatial_block_id` (GroupKFold-style): a block is never split.
- Training rows within 5000 m of a validation block are marked `buffer` and must be dropped from that fold's training set.
- `event_cluster_id` groups positives in space+time for Leave-One-Event-Cluster-Out CV.
- Temporal split is a true out-of-time hold-out (train ≤ 2015-12-31, val ≤ 2018-12-31, test after).
- `final_test` rows are locked: never use for any fitting, HPO, or threshold choice.