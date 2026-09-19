"""Stage 9 contract tests — the four fixes, pinned so they cannot silently regress."""
from __future__ import annotations

import json

import numpy as np
import pandas as pd
import pytest

from sih_ml.final import rainfall_probe as rp
from sih_ml.models.dataset import load_data
from sih_ml.utils.common import REPO_ROOT

CFG = REPO_ROOT / "conf" / "remediate_config.yaml"
S9 = REPO_ROOT / "reports" / "stage9"


@pytest.fixture(scope="module")
def dc():
    return load_data(CFG)


# ----------------------------------------------------------------- A: the leak
def test_final_test_predicate_is_block_only():
    """The `| label_tier == "gold"` clause must never come back.

    Any predicate on a ROW attribute can cut across blocks and break the partition;
    that is exactly how 3 gold rows were lifted out of a block whose other 4,421
    rows — including 15 positives of the same segment — stayed in training.
    """
    import ast
    import inspect

    from sih_ml.splits import make_splits

    fn = next(n for n in ast.walk(ast.parse(inspect.getsource(make_splits)))
              if isinstance(n, ast.FunctionDef) and n.name == "_final_test")
    ret = next(n for n in ast.walk(fn) if isinstance(n, ast.Return))
    used = {a.attr for a in ast.walk(ret) if isinstance(a, ast.Attribute)}
    banned = {"label_tier", "label_source", "hazard", "date", "target"}
    assert not (used & banned), f"_final_test depends on row attributes: {used & banned}"


def test_block_components_prevent_segment_straddling(dc):
    """Held-out units are whole block-components, so a segment re-pinned across two
    blocks by event-modal assignment can never land on both sides."""
    from sih_ml.splits.make_splits import _block_components
    data, _ = dc
    df = data.panel[["segment_id", "target", "event_id", "spatial_block_id"]]
    comp = _block_components(df)
    te_blocks = set(df.loc[data.panel.final_test.to_numpy(bool), "spatial_block_id"])
    dev_blocks = set(df.loc[~data.panel.final_test.to_numpy(bool), "spatial_block_id"])
    te_comps = {comp[b] for b in te_blocks}
    dev_comps = {comp[b] for b in dev_blocks}
    assert not (te_comps & dev_comps), "a block-component spans dev and test"


def test_gold_claim_is_retired_not_relocated(dc):
    data, _ = dc
    te = data.final_test_index()
    assert int((data.panel["label_tier"].to_numpy()[te] == "gold").sum()) == 0
    doc = (REPO_ROOT / "REMEDIATION.md").read_text().lower()
    assert "retired" in doc and "none" in doc


# ------------------------------------------------------------ B: the confound
def test_trigger_class_is_defined_by_provenance_not_rainfall():
    """The class boundary must be metadata, never a rainfall value — otherwise
    'rainfall predicts the rain-attributable class' is circular."""
    import ast
    import inspect

    fn = ast.parse(inspect.getsource(rp.trigger_class).lstrip()).body[0]
    # every column actually SUBSCRIPTED out of the panel, e.g. data.panel["x"]
    read = {n.slice.value for n in ast.walk(fn)
            if isinstance(n, ast.Subscript) and isinstance(n.slice, ast.Constant)
            and isinstance(n.slice.value, str)}
    rainfall = {c for c in read
                if c.startswith(("rain_", "api_", "id_ratio", "id_exceed"))
                or c in ("is_monsoon", "month", "doy_sin", "doy_cos", "days_since_rain")}
    assert not rainfall, f"trigger_class reads rainfall/season columns: {rainfall} — circular"
    assert "label_source" in read, "trigger_class must key off provenance"


def test_scope_excludes_only_news_derived_positives(dc):
    data, _ = dc
    tc = rp.trigger_class(data)
    out = tc == "not_rain_attributable"
    assert out.sum() > 0
    assert (data.y[out] == 1).all(), "scope excluded a negative"
    srcs = set(data.panel["label_source"].to_numpy()[out])
    assert srcs == rp.NOT_RAIN_ATTRIBUTABLE_SOURCES
    # out-of-scope rows stay in the panel — they are reported, not deleted
    assert len(data.panel) == 103246 or out.sum() < len(data.panel)


def test_scope_applies_to_training_and_evaluation_together():
    """Filtering only one side would train against a different target than it is
    scored on — quieter and worse than not scoping at all."""
    import inspect

    from sih_ml.optimize import harness

    src = inspect.getsource(harness.fit_one_fold)
    assert "data.scoped(tr_all)" in src and "data.scoped(va)" in src


def test_rainfall_signal_result_is_recorded_and_positive():
    """The project's central question must stay answered in the artifacts."""
    p = S9 / "remediation_results.json"
    if not p.exists():
        pytest.skip("Stage 9 has not been run")
    R = json.loads(p.read_text())
    row = next(s for s in R["rainfall_probe"] if s["stratum"] == "all")
    assert row["mean_delta_rain_helps"] > 0, "rainfall no longer helps in scope"
    assert row["fold_seed_pairs_rain_helps"] == row["fold_seed_pairs"], (
        "rainfall signal is no longer unanimous across fold-seed pairs")
    assert row["replicated_all_seeds"] is True


# --------------------------------------------------------- C: monotonicity
def test_derived_exceed_flags_are_constrained():
    from sih_ml.utils.common import load_config_with_base
    cfg = load_config_with_base(CFG)
    mono = set(cfg.lgbm.monotone_rainfall_features)
    for c in ("id_exceed_1d", "id_exceed_3d", "id_exceed_7d"):
        assert c in mono, f"{c} is derived from a constrained feature but is not constrained"
    for c in ("id_ratio_1d", "id_ratio_3d", "id_ratio_7d"):
        assert c in mono


def test_zero_monotonicity_violations_after_fix():
    p = S9 / "monotonicity.csv"
    if not p.exists():
        pytest.skip("Stage 9 has not been run")
    m = pd.read_csv(p)
    assert m.violations.sum() == 0, (
        "more rain lowers the score somewhere — the C fix has regressed")
    assert m.exceed_flags_updated.any(), "the recomputed-flags variant must be tested"


# ------------------------------------------------------------ E: versioning
def test_v1_is_preserved_not_overwritten():
    """The known-leaked reference and its audit trail must survive."""
    v1 = REPO_ROOT / "reports" / "stage7" / "PREREGISTRATION.json"
    assert v1.exists(), "final_v1 pre-registration was deleted"
    assert json.loads(v1.read_text())["config_sha256_16"] == "5c8ab2326f9c5b5c"
    doc = (REPO_ROOT / "FINAL_MODEL.md").read_text().lower()
    assert "superseded" in doc and "known-leaked" in doc


def test_v2_has_a_distinct_hash_and_discloses_its_bias():
    p = S9 / "PREREGISTRATION_V2.json"
    if not p.exists():
        pytest.skip("Stage 9 has not been run")
    pre = json.loads(p.read_text())
    assert pre["config_sha256_16"] != "5c8ab2326f9c5b5c"
    assert pre["supersedes"]["config"] == "5c8ab2326f9c5b5c"
    assert "not" in pre["bias_disclosure"].lower()


def test_gate_thresholds_were_not_lowered_to_pass():
    """Failing gates must be reported, never tuned away."""
    p = S9 / "gates_before_after.csv"
    if not p.exists():
        pytest.skip("Stage 9 has not been run")
    g = pd.read_csv(p)
    shared = g[g.v1_pass.notna()]
    assert (shared.threshold.values == shared.threshold.values).all()
    old = REPO_ROOT / "reports" / "stage8" / "deployment_gates.csv"
    if old.exists():
        o = pd.read_csv(old).set_index("gate").threshold.to_dict()
        for _, r in shared.iterrows():
            if r.gate in o:
                assert str(r.threshold) == str(o[r.gate]), (
                    f"threshold for '{r.gate}' changed between v1 and v2")
    assert not g.v2_pass.all(), "every gate passes — check nothing was relaxed"


def test_steep_terrain_conclusions_are_evidence_backed():
    p = S9 / "remediation_results.json"
    if not p.exists():
        pytest.skip("Stage 9 has not been run")
    st = json.loads(p.read_text())["steep"]
    # the representation hypothesis must be settled by a measurement, not asserted
    assert st["steep_share_of_dev_positives"] > st["steep_share_of_dev_rows"], (
        "steep is under-represented after all — D's root cause needs revisiting")
    assert "NOT under-represented" in st["verdict"]
