import pandas as pd


def test_every_row_has_a_fold(panel, folds):
    m = panel.merge(folds, on=["segment_id", "date"], how="left")
    assert m.spatial_fold.notna().all()
    assert m.temporal_split.notna().all()


def test_spatial_fold_roles_consistent(folds, cfg):
    k = cfg.split.n_spatial_folds
    for f in range(k):
        role = folds[f"spatial_role_f{f}"]
        assert (folds.loc[role == "val", "spatial_fold"] == f).all()
        assert set(role.unique()) <= {"train", "val", "buffer", "test"}
        # 'test' role <=> locked final-test row
        assert (folds.loc[role == "test", "final_test"]).all()


def test_buffer_never_in_train_or_val(folds, cfg):
    for f in range(cfg.split.n_spatial_folds):
        role = folds[f"spatial_role_f{f}"]
        # a buffer row is neither counted as train nor val
        assert ((role == "buffer") & (folds.spatial_fold == f)).sum() == 0


def test_each_fold_has_positives(panel, folds, cfg):
    m = panel.merge(folds, on=["segment_id", "date"])
    for f in range(cfg.split.n_spatial_folds):
        pos = ((m.spatial_fold == f) & (m.target == 1)).sum()
        assert pos > 0, f"fold {f} has no positive val rows"


def test_temporal_order(folds):
    d = folds.groupby("temporal_split").agg(mn=("split_date", "min"), mx=("split_date", "max"))
    assert d.loc["train", "mx"] < d.loc["val", "mn"]
    assert d.loc["val", "mx"] < d.loc["test", "mn"]


def test_final_test_is_locked_and_nonempty(panel, folds):
    m = panel.merge(folds[["segment_id", "date", "final_test"]], on=["segment_id", "date"])
    assert m.final_test.sum() > 0


def test_final_test_membership_is_a_function_of_the_block_alone(panel, folds):
    """The locked split must be a union of WHOLE spatial blocks — nothing else.

    This test replaces one that asserted `gold rows are all in final_test`, which
    was asserting the bug: the `| label_tier == "gold"` clause pulled 3 verified rows
    out of a block that otherwise stayed entirely in training, taking them away from
    15 positive rows of the same segment. Any predicate on a ROW attribute (tier,
    source, date, hazard) can cut across blocks and silently break the partition, so
    the invariant worth pinning is the structural one, not the gold one.
    """
    m = panel.merge(folds[["segment_id", "date", "final_test", "spatial_block_id"]],
                    on=["segment_id", "date"])
    per_block = m.groupby("spatial_block_id").final_test.nunique()
    split_blocks = per_block[per_block > 1].index.tolist()
    assert not split_blocks, f"blocks straddling the dev/test boundary: {split_blocks}"


def test_no_segment_or_event_spans_dev_and_locked_test(panel, folds):
    """The automated leakage gate, asserted on the shipped artifact.

    A segment's static terrain columns are an exact per-segment fingerprint, so a
    segment present on both sides lets the model recognise a test row with no weather
    skill at all — measured in Stage 8 as a gold row holding its 99th-percentile rank
    even with every rainfall input deleted.
    """
    m = panel.merge(folds[["segment_id", "date", "final_test"]], on=["segment_id", "date"])
    dev, te = m[~m.final_test], m[m.final_test]
    assert not (set(dev.segment_id) & set(te.segment_id)), "segment spans dev and test"
    pos_ev = lambda d: set(d.loc[d.target == 1, "event_id"].dropna().astype(str))
    assert not (pos_ev(dev) & pos_ev(te)), "positive event spans dev and test"


def test_leakage_gate_is_enforced_at_build_time(cfg):
    """The gate must run inside `make_splits`, not as a downstream audit.

    The original leak survived three stages because the check was a one-off analysis
    performed afterwards. A build-time gate that raises cannot be forgotten.
    """
    import ast
    import inspect

    from sih_ml.splits import make_splits

    src = inspect.getsource(make_splits)
    assert "def assert_no_split_leakage" in src
    tree = ast.parse(src)
    main_fn = next(n for n in ast.walk(tree)
                   if isinstance(n, ast.FunctionDef) and n.name == "main")
    called = {n.func.id for n in ast.walk(main_fn)
              if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
    assert "assert_no_split_leakage" in called, "gate is defined but never called by main()"
    gate = next(n for n in ast.walk(tree)
                if isinstance(n, ast.FunctionDef) and n.name == "assert_no_split_leakage")
    assert any(isinstance(n, ast.Raise) for n in ast.walk(gate)), "gate must raise, not warn"


def test_event_clusters_exist(folds):
    assert folds.event_cluster_id.nunique() > 20
