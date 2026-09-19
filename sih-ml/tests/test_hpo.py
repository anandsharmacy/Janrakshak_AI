"""Stage 6 tests: config chain, the P0 ES fix, search-space hygiene, and the
selection/report separation that keeps HPO honest."""
import json

import numpy as np
import pandas as pd
import pytest

from sih_ml.models.dataset import load_data
from sih_ml.train import cv, hpo
from sih_ml.utils.common import REPO_ROOT, Config, load_config_with_base, resolve

HPO_CFG = REPO_ROOT / "conf" / "hpo_config.yaml"


@pytest.fixture(scope="module")
def cfg():
    return load_config_with_base(HPO_CFG)


# ------------------------------------------------------- recursive config chain
def test_config_chain_resolves_all_levels(cfg):
    """hpo_config -> train_config -> model_baseline. Resolving only one level
    silently dropped every key defined two levels down (this bit us for real)."""
    assert cfg.model_version == "hpo_v1"                 # from hpo_config
    assert cfg.lgbm.early_stopping_metric == "pr_auc"    # from train_config
    assert cfg.cv.drop_buffer_rows is True               # from model_baseline
    assert cfg.cv.n_spatial_folds == 5                   # from model_baseline
    assert "base_config" not in cfg                      # consumed, not leaked


def test_circular_base_config_is_rejected(tmp_path):
    a, b = tmp_path / "a.yaml", tmp_path / "b.yaml"
    a.write_text(f"base_config: {b}\nx: 1\n")
    b.write_text(f"base_config: {a}\ny: 2\n")
    with pytest.raises(ValueError, match="circular"):
        load_config_with_base(a)


# ------------------------------------------------------------ the P0 ES fix
def test_hpo_uses_event_grouped_es(cfg):
    """HPO against the old row-split signal is meaningless (ES AP was 0.999)."""
    assert cfg.cv.es_split_mode == "event"


def test_event_grouped_split_keeps_events_whole():
    events = np.array(["E1"] * 20 + ["E2"] * 20 + ["E3"] * 20 + [""] * 200)
    y = np.array([1] * 60 + [0] * 200)
    tr, es = cv.event_grouped_es_split(events, y, frac=0.34, seed=0)
    tr_ev = set(events[tr & (y == 1)])
    es_ev = set(events[es & (y == 1)])
    assert tr_ev and es_ev
    assert not (tr_ev & es_ev), "an event appeared on both sides of the ES split"


def test_event_grouped_split_includes_negatives_on_both_sides():
    events = np.array(["E1"] * 20 + [""] * 100)
    y = np.array([1] * 20 + [0] * 100)
    tr, es = cv.event_grouped_es_split(events, y, frac=0.2, seed=0)
    assert (y[es] == 0).sum() > 0 and (y[tr] == 0).sum() > 0


def test_es_dispatcher_honours_mode():
    data, mcfg = load_data(HPO_CFG)
    idx = np.arange(min(4000, len(data.panel)))
    ev_cfg = Config({**dict(mcfg), "cv": {**dict(mcfg.cv), "es_split_mode": "event"}})
    row_cfg = Config({**dict(mcfg), "cv": {**dict(mcfg.cv), "es_split_mode": "row"}})
    a = cv.make_es_split(data, idx, ev_cfg, 0)
    b = cv.make_es_split(data, idx, row_cfg, 0)
    assert not np.array_equal(a[1], b[1]), "event and row modes produced identical splits"


# ---------------------------------------------------------- search space hygiene
def test_search_space_excludes_uninformative_params(cfg):
    """Params we deliberately do NOT search must stay out of the space."""
    space = dict(cfg.hpo.space)
    for banned in ("max_bin", "boosting_type", "objective", "n_estimators", "verbosity"):
        assert banned not in space


def test_search_space_covers_capacity_and_regularization(cfg):
    """Stage 5 measured in-sample AP 0.9999 -> capacity/regularization must be searched."""
    space = dict(cfg.hpo.space)
    for required in ("num_leaves", "max_depth", "min_child_samples",
                     "reg_alpha", "reg_lambda", "learning_rate"):
        assert required in space


def test_params_to_cfg_applies_and_can_disable_monotone(cfg):
    p = {"num_leaves": 7, "learning_rate": 0.077, "use_monotone": False,
         "scale_pos_weight_mult": 2.0}
    out = hpo.params_to_cfg(cfg, p, n_estimators=321, early_stopping_rounds=11)
    assert out.lgbm.num_leaves == 7
    assert out.lgbm.learning_rate == pytest.approx(0.077)
    assert out.lgbm.n_estimators == 321
    assert out.lgbm.monotone_rainfall_features == []
    # meta-params must NOT be injected as lgbm kwargs
    assert "use_monotone" not in out.lgbm
    assert "scale_pos_weight_mult" not in out.lgbm


def test_params_to_cfg_keeps_monotone_when_enabled(cfg):
    out = hpo.params_to_cfg(cfg, {"use_monotone": True}, 100, 10)
    assert len(out.lgbm.monotone_rainfall_features) > 0


# ------------------------------------------------- selection / report separation
def test_selection_and_report_folds_are_disjoint(cfg):
    sel, rep = set(cfg.hpo.selection_folds), set(cfg.hpo.report_folds)
    assert sel and rep
    assert not (sel & rep), "the search would be optimising the folds it reports on"
    assert sel | rep <= set(range(cfg.cv.n_spatial_folds))


def test_report_folds_untouched_by_objective(cfg):
    """The Optuna objective must only ever fit/score selection folds."""
    import inspect
    src = inspect.getsource(hpo.make_objective)
    assert "selection_folds" in src
    assert "report_folds" not in src


# ------------------------------------------------------------- artifact checks
def test_stage6_artifacts_and_honest_verdict():
    mcfg = load_config_with_base(HPO_CFG)
    rdir = resolve(mcfg, mcfg.paths.reports)
    p = rdir / "hpo_results.json"
    if not p.exists():
        pytest.skip("run `make stage6` first")
    r = json.loads(p.read_text())
    for k in ("E0_baseline_row_es", "E1_event_grouped_es", "E2_hpo", "model_selection"):
        assert k in r
    ms = r["model_selection"]
    # the verdict must be computed against the noise floor, not raw argmax
    assert "improvement_exceeds_noise" in ms
    assert isinstance(ms["improvement_exceeds_noise"], bool)
    assert (rdir / "best_params.json").exists()
    assert (rdir / "hpo_trials.csv").exists()


def test_final_test_never_touched_in_stage6():
    """No Stage 6 code path may reference the locked split.

    Checks the AST, not raw text — the module docstrings legitimately *mention*
    `final_test` to say they don't use it, and a substring match flags that."""
    import ast
    import inspect

    from sih_ml.train import finetune

    for mod in (hpo, finetune):
        tree = ast.parse(inspect.getsource(mod))
        hits = []
        for node in ast.walk(tree):
            # attribute access like df.final_test
            if isinstance(node, ast.Attribute) and node.attr == "final_test":
                hits.append(f"attribute at line {node.lineno}")
            # column/string use like df["final_test"]
            elif isinstance(node, ast.Constant) and node.value == "final_test":
                hits.append(f"string literal at line {node.lineno}")
            elif isinstance(node, ast.Name) and node.id == "final_test":
                hits.append(f"name at line {node.lineno}")
        assert not hits, f"{mod.__name__} touches final_test: {hits}"
