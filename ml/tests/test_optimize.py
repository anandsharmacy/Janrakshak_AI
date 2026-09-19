"""Stage 7 contract tests — leakage firewall, loss correctness, augmentation
meaning-preservation, honest comparison, and the locked-test guard."""
from __future__ import annotations

import ast
import importlib
import inspect
import json

import numpy as np
import pandas as pd
import pytest

from sih_ml.models.dataset import load_data
from sih_ml.optimize import augment, calibrate, composite, data_opt, ensemble
from sih_ml.optimize.harness import (Arm, TrainSet, fit_one_fold, paired_delta,
                                     run_arm, verdict)
from sih_ml.optimize.losses import _focal_grad, focal_loss_value, make_focal_objective
from sih_ml.train import cv as CV
from sih_ml.utils.common import REPO_ROOT

CFG = REPO_ROOT / "conf" / "optimize_config.yaml"


@pytest.fixture(scope="module")
def dc():
    return load_data(CFG)


# --------------------------------------------------------------------------- #
# The leakage firewall
# --------------------------------------------------------------------------- #
def test_arm_never_sees_validation_or_earlystop_rows(dc):
    """The core Stage 7 contract: an arm may only transform TRAINING rows.

    If an arm could see the held-out fold it could trivially fabricate a gain, and
    if it could see the early-stopping rows it would corrupt the inner validation
    signal Stage 5 fought to restore. `fit_one_fold` is the only caller, so this
    pins the property at its source.
    """
    data, cfg = dc
    seen = {}

    def spy(d, tr_idx, fold, seed):
        seen["idx"] = np.asarray(tr_idx)
        return TrainSet(d.X(tr_idx), d.y[tr_idx], d.w[tr_idx])

    fold = 0
    tr_all, va = data.spatial_fold_indices(fold, drop_buffer=cfg.cv.drop_buffer_rows)
    m_tr, m_es = CV.make_es_split(data, tr_all, cfg, cfg.seed + fold)
    es = tr_all[m_es]

    fit_one_fold(data, cfg, Arm("spy", "test", spy), fold, cfg.seed)
    got = set(seen["idx"].tolist())
    assert not (got & set(va.tolist())), "arm received held-out validation rows"
    assert not (got & set(es.tolist())), "arm received early-stopping rows"
    assert got == set(tr_all[m_tr].tolist())


def test_inner_prospector_uses_only_training_rows(dc):
    """Mining scores must be cross-fitted INSIDE the fold's training rows.

    Using Stage 5's pooled OOF instead would leak: a training row of fold k was
    validated by a model that trained on fold k's held-out blocks.
    """
    data, cfg = dc
    src = inspect.getsource(data_opt.inner_oof_scores)
    tree = ast.parse(src)
    banned = {"spatial_fold_indices", "dev_mask", "final_test_index"}
    calls = {n.func.attr for n in ast.walk(tree)
             if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)}
    assert not (calls & banned), f"prospector reaches outside its fold: {calls & banned}"

    tr, _ = data.spatial_fold_indices(0, drop_buffer=True)
    tr = tr[:6000]
    s = data_opt.inner_oof_scores(data, cfg, tr, cfg.seed, n_inner=2)
    assert len(s) == len(tr) and np.isfinite(s).all()


def test_stage7_optimize_modules_never_touch_final_test():
    """Only train/final_test.py may read the locked split."""
    mods = ["sih_ml.optimize.harness", "sih_ml.optimize.data_opt",
            "sih_ml.optimize.augment", "sih_ml.optimize.losses",
            "sih_ml.optimize.ensemble", "sih_ml.optimize.calibrate",
            "sih_ml.optimize.threshold", "sih_ml.optimize.stratified",
            "sih_ml.optimize.composite", "sih_ml.optimize.runtime",
            "sih_ml.train.run_optimize"]
    for name in mods:
        mod = importlib.import_module(name)
        tree = ast.parse(inspect.getsource(mod))
        hits = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and node.attr in ("final_test",
                                                                 "final_test_index"):
                hits.append(node.attr)
            elif isinstance(node, ast.Constant) and node.value == "final_test":
                hits.append("final_test")
        assert not hits, f"{name} touches final_test: {set(hits)}"


def test_final_test_opener_requires_preregistration():
    """The locked split cannot be opened without a pre-registered config."""
    src = inspect.getsource(importlib.import_module("sih_ml.train.final_test"))
    assert "PREREGISTRATION.json" in src
    assert "REFUSING" in src, "opener must hard-fail without pre-registration"
    tree = ast.parse(src)
    raises = [n for n in ast.walk(tree) if isinstance(n, ast.Raise)]
    assert raises, "opener must raise, not warn, when pre-registration is missing"


# --------------------------------------------------------------------------- #
# Focal loss
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize("gamma", [0.0, 1.0, 2.0, 3.0])
def test_focal_gradient_matches_numerical_derivative(gamma):
    rng = np.random.default_rng(0)
    z = rng.normal(0, 2, size=200)
    y = (rng.random(200) > 0.5).astype(float)
    eps, alpha = 1e-6, 0.25
    ana = _focal_grad(z, y, gamma, alpha)
    for i in range(0, 200, 17):
        zp, zm = z.copy(), z.copy()
        zp[i] += eps; zm[i] -= eps
        num = (focal_loss_value(zp, y, gamma, alpha)
               - focal_loss_value(zm, y, gamma, alpha)) / (2 * eps) * len(z)
        assert abs(num - ana[i]) <= 1e-4 * max(1.0, abs(ana[i]))


def test_focal_gamma_zero_reduces_to_weighted_logloss():
    """gamma=0 removes the focusing term, leaving alpha-weighted cross-entropy
    whose gradient is alpha_t*(p-y). A regression here means the derivation drifted."""
    rng = np.random.default_rng(1)
    z = rng.normal(0, 1.5, size=500)
    y = (rng.random(500) > 0.5).astype(float)
    p = 1 / (1 + np.exp(-z))
    assert np.allclose(_focal_grad(z, y, 0.0, 0.5), 0.5 * (p - y), atol=1e-9)


def test_focal_objective_applies_sample_weights_and_positive_hessian():
    """LightGBM does NOT apply sample_weight to a custom objective — the closure
    must do it, or Stage 2's label-confidence weights are silently discarded."""
    import lightgbm as lgb
    rng = np.random.default_rng(2)
    X = rng.random((200, 3))
    y = (rng.random(200) > 0.5).astype(float)
    z = rng.normal(0, 1, 200)
    fobj = make_focal_objective(2.0, 0.25)

    d1 = lgb.Dataset(X, label=y, weight=np.ones(200), free_raw_data=False); d1.construct()
    d2 = lgb.Dataset(X, label=y, weight=np.full(200, 3.0), free_raw_data=False); d2.construct()
    g1, h1 = fobj(z, d1)
    g2, h2 = fobj(z, d2)
    assert np.allclose(g2, 3.0 * g1) and np.allclose(h2, 3.0 * h1)
    assert (h1 > 0).all(), "LightGBM requires a strictly positive Hessian"


def test_custom_objective_predictions_are_probabilities(dc):
    """With a custom objective LightGBM emits raw margins; the wrapper must apply
    the sigmoid or every downstream probability, calibrator and threshold is wrong."""
    data, cfg = dc
    arm = Arm("focal", "loss", None, objective="focal",
              objective_kwargs={"gamma": 2.0, "alpha": 0.25})
    ap, va, pred, model, _, _ = fit_one_fold(data, cfg, arm, 0, cfg.seed)
    assert model.raw_score_ is True
    assert pred.min() >= 0.0 and pred.max() <= 1.0
    assert np.isfinite(ap)


# --------------------------------------------------------------------------- #
# Augmentation meaning-preservation
# --------------------------------------------------------------------------- #
def test_rainfall_jitter_keeps_derived_columns_consistent(dc):
    """Rainfall windows and their intensity-duration ratios are one process. If
    jitter scales rain but not id_ratio (or leaves id_exceed stale), it manufactures
    physically impossible rows."""
    data, _ = dc
    X = data.X(np.arange(3000)).copy()
    rng = np.random.default_rng(0)
    J = augment.rainfall_jitter(X, 0.3, rng)

    f = J["rain_1d_mm"].to_numpy(float) / np.where(
        X["rain_1d_mm"].to_numpy(float) == 0, np.nan, X["rain_1d_mm"].to_numpy(float))
    ok = np.isfinite(f)
    for c in ["rain_7d_mm", "api_mm", "id_ratio_3d"]:
        g = J[c].to_numpy(float) / np.where(X[c].to_numpy(float) == 0, np.nan,
                                            X[c].to_numpy(float))
        m = ok & np.isfinite(g)
        assert np.allclose(f[m], g[m], rtol=1e-9), f"{c} did not scale with rainfall"
    for rc, fc in zip(augment.ID_RATIO_COLS, augment.ID_EXCEED_COLS):
        assert (J[fc].to_numpy(float)
                == (J[rc].to_numpy(float) >= 1.0).astype(float)).all(), \
            f"{fc} is stale w.r.t. {rc}"


def test_rainfall_jitter_leaves_exact_measurements_alone(dc):
    """Terrain and date columns describe things measured exactly; the
    physics-preserving arm must not touch them."""
    data, _ = dc
    X = data.X(np.arange(3000)).copy()
    J = augment.rainfall_jitter(X, 0.5, np.random.default_rng(0))
    for c in augment.FROZEN_COLS:
        if c in X:
            a, b = X[c].to_numpy(float), J[c].to_numpy(float)
            m = np.isfinite(a) & np.isfinite(b)
            assert np.array_equal(a[m], b[m]), f"{c} was perturbed"


def test_gaussian_all_does_perturb_terrain(dc):
    """The contrast arm must actually differ from the physics-preserving one,
    otherwise the comparison between them is meaningless."""
    data, _ = dc
    X = data.X(np.arange(3000)).copy()
    num = [c for c in data.features if c not in data.categorical]
    G = augment.gaussian_all(X, 0.1, np.random.default_rng(0), num)
    a, b = X["slope_mean_deg"].to_numpy(float), G["slope_mean_deg"].to_numpy(float)
    m = np.isfinite(a) & np.isfinite(b)
    assert not np.allclose(a[m], b[m])


def test_smote_stays_inside_spatial_blocks_and_only_adds_positives(dc):
    data, _ = dc
    tr, _ = data.spatial_fold_indices(0, drop_buffer=True)
    tr = tr[:20000]
    ts = augment.smote_positives(data, tr, 5, 0.5, np.random.default_rng(0))
    n0 = len(tr)
    assert len(ts.y) >= n0
    assert (ts.y[n0:] == 1).all(), "SMOTE must only synthesise positives"
    assert np.array_equal(ts.y[:n0], data.y[tr]), "original rows were altered"
    if len(ts.y) > n0:
        w_pos = data.w[tr][data.y[tr] == 1]
        assert ts.w[n0:].max() <= w_pos.max() + 1e-9, \
            "synthetic rows must not outrank observed data"


# --------------------------------------------------------------------------- #
# Data arms
# --------------------------------------------------------------------------- #
def test_dedup_removes_only_duplicates(dc):
    data, _ = dc
    tr, _ = data.spatial_fold_indices(0, drop_buffer=True)
    kept = data_opt.dedup_indices(data, tr)
    assert len(kept) <= len(tr)
    assert set(kept.tolist()) <= set(tr.tolist())
    sub = data.panel.iloc[kept][data.features]
    assert not pd.util.hash_pandas_object(sub, index=False).duplicated().any()


def test_confidence_floor_never_drops_negatives(dc):
    data, _ = dc
    tr, _ = data.spatial_fold_indices(0, drop_buffer=True)
    ts = data_opt.make_confidence_floor_arm(0.35)(data, tr, 0, 42)
    assert int((data.y[tr] == 0).sum()) == int((ts.y == 0).sum())
    assert int(ts.y.sum()) <= int(data.y[tr].sum())


@pytest.mark.parametrize("scheme", ["uniform", "sqrt", "square"])
def test_weight_schemes_preserve_total_mass(scheme, dc):
    """A weight scheme must change the SHAPE of the weights, not their total — else
    it is a learning-rate change in disguise and the arm measures the wrong thing."""
    data, _ = dc
    tr, _ = data.spatial_fold_indices(0, drop_buffer=True)
    ts = data_opt.make_weight_scheme_arm(scheme)(data, tr, 0, 42)
    assert ts.w.sum() == pytest.approx(data.w[tr].sum(), rel=1e-9)


def test_mining_redistributes_weight_without_adding_it(dc):
    """Same reasoning: upweighting hard negatives must not also raise total negative
    mass, or the arm confounds 'better-chosen weight' with 'more weight'."""
    data, cfg = dc
    tr, _ = data.spatial_fold_indices(0, drop_buffer=True)
    tr = tr[:8000]
    ts = data_opt.make_hard_negative_arm(cfg, 3.0, 2)(data, tr, 0, 42)
    neg = data.y[tr] == 0
    assert ts.w[neg].sum() == pytest.approx(data.w[tr][neg].sum(), rel=1e-6)
    assert ts.w[neg].std() > data.w[tr][neg].std() * 0.5, "no redistribution happened"


# --------------------------------------------------------------------------- #
# Honest comparison
# --------------------------------------------------------------------------- #
def test_paired_delta_of_identical_runs_is_zero():
    r = {"fold_ap": {0: 0.3, 1: 0.5, 2: 0.2, 3: 0.4, 4: 0.1}}
    d = paired_delta(r, r, [0, 1, 2, 3, 4], 2000, 0)
    assert d["mean_delta"] == 0.0 and d["p_value"] == pytest.approx(1.0)
    assert verdict(d, 4, 0.10) == "not demonstrated"


def test_permutation_p_cannot_go_below_its_floor():
    """With 5 folds the smallest attainable two-sided p is 2/2^5 = 0.0625. A
    reported p below that is a bug — and Monte Carlo sampling produces exactly that
    bug (0.0619 observed), which is why small n is enumerated exhaustively."""
    a = {"fold_ap": {i: 0.5 for i in range(5)}}
    b = {"fold_ap": {i: 0.1 for i in range(5)}}
    d = paired_delta(a, b, list(range(5)), 50000, 0)
    assert d["exact_permutation"] is True
    assert d["folds_improved"] == 5
    assert d["p_value"] == pytest.approx(2.0 / 32)
    assert d["min_attainable_p"] == pytest.approx(2.0 / 32)


def test_permutation_is_exact_whenever_the_space_is_small_enough():
    """2^n <= n_perm must enumerate, not sample — an exact answer should never be
    approximated. Above that the sampler takes over."""
    rng = np.random.default_rng(0)
    ap = {i: float(v) for i, v in enumerate(rng.random(5))}
    bp = {i: float(v) for i, v in enumerate(rng.random(5))}
    assert paired_delta({"fold_ap": ap}, {"fold_ap": bp}, list(range(5)), 64, 0)[
        "exact_permutation"] is True
    assert paired_delta({"fold_ap": ap}, {"fold_ap": bp}, list(range(5)), 16, 0)[
        "exact_permutation"] is False
    # exact enumeration is deterministic: the seed must not change the answer
    p1 = paired_delta({"fold_ap": ap}, {"fold_ap": bp}, list(range(5)), 20000, 1)["p_value"]
    p2 = paired_delta({"fold_ap": ap}, {"fold_ap": bp}, list(range(5)), 20000, 999)["p_value"]
    assert p1 == p2


def test_verdict_requires_both_consistency_and_significance():
    strong = {"mean_delta": 0.05, "folds_improved": 5, "n_folds": 5, "p_value": 0.06}
    assert verdict(strong, 4, 0.10) == "improvement"
    inconsistent = {"mean_delta": 0.05, "folds_improved": 3, "n_folds": 5, "p_value": 0.06}
    assert verdict(inconsistent, 4, 0.10) == "not demonstrated"
    noisy = {"mean_delta": 0.05, "folds_improved": 5, "n_folds": 5, "p_value": 0.40}
    assert verdict(noisy, 4, 0.10) == "not demonstrated"
    bad = {"mean_delta": -0.05, "folds_improved": 0, "n_folds": 5, "p_value": 0.06}
    assert verdict(bad, 4, 0.10) == "regression"


def test_ensemble_weights_are_not_fitted_on_the_fold_they_score(dc):
    """Leave-one-fold-out weight selection. Choosing weights on the same OOF rows
    you then report is selection-on-evaluation and always produces a 'gain'."""
    data, _ = dc
    rng = np.random.default_rng(0)
    n = len(data.panel)
    fold_of = np.full(n, -1)
    idx = np.arange(n)
    for f in range(5):
        fold_of[idx[f::5]] = f
    members = {"a": rng.random(n), "b": rng.random(n)}
    out = ensemble.blend_oof(members, data, fold_of, [0, 1, 2, 3, 4], step=0.25)
    assert set(out["weights_per_fold"]) == {0, 1, 2, 3, 4}
    for f, w in out["weights_per_fold"].items():
        assert abs(sum(w.values()) - 1.0) < 1e-9
    src = inspect.getsource(ensemble.blend_oof)
    assert "others" in src and "g != f" in src


def test_calibration_is_cross_fitted(dc):
    """Fold k must be calibrated by a model fitted on the other folds only."""
    data, _ = dc
    rng = np.random.default_rng(0)
    n = len(data.panel)
    fold_of = np.full(n, -1)
    sel = np.arange(0, n, 7)
    for i, j in enumerate(sel):
        fold_of[j] = i % 5
    oof = np.full(n, np.nan)
    oof[sel] = rng.random(len(sel))
    out = calibrate.cross_fitted_calibration(data, oof, fold_of, [0, 1, 2, 3, 4], None)
    assert np.isfinite(out[sel]).all()
    assert not np.isfinite(out[fold_of == -1]).any(), "unscored rows were calibrated"
    src = inspect.getsource(calibrate.cross_fitted_calibration)
    assert "fold_of != f" in src


def test_calibration_separates_fixable_from_unfixable_axes(dc):
    """Terrain miscalibration can be corrected at inference; region miscalibration
    cannot (a new area's base rate is unknown). Pooling them hides a real fix."""
    src = inspect.getsource(calibrate.compare_calibrators)
    assert "worst_slope_ratio" in src and "worst_region_ratio" in src


# --------------------------------------------------------------------------- #
# Composite
# --------------------------------------------------------------------------- #
def test_composite_applies_steps_in_the_declared_order(dc):
    """filters -> weights -> features -> rows. If weights ran before filters, the
    mining percentiles would refer to rows that no longer exist."""
    data, cfg = dc
    tr, _ = data.spatial_fold_indices(0, drop_buffer=True)
    tr = tr[:12000]
    order = []
    arm = composite.make_composite_arm(
        filters=[lambda d, i, f, s: (order.append("filter"), i[: len(i) // 2])[1]],
        weights=[lambda d, i, w, f, s: (order.append("weight"), w * 2)[1]],
        features=[lambda d, X, f, s: (order.append("feature"), X)[1]],
        rows=[lambda d, i, X, y, w, f, s: (order.append("row"), TrainSet(X, y, w))[1]],
    )
    ts = arm(data, tr, 0, 42)
    assert order == ["filter", "weight", "feature", "row"]
    assert len(ts.y) == len(tr) // 2


def test_composite_registry_covers_every_arm_family(dc):
    """A family missing from the composite adapter is silently dropped — the
    composite then reports a combination that does not contain the winners."""
    from sih_ml.train.run_optimize import _composite_from, build_arms
    data, cfg = dc
    names = [a.name for a in build_arms(cfg)]
    # the append variant deliberately supersedes in-place rainfall jitter (applying
    # both would perturb the same rows twice), so exclude it when checking coverage
    names = [n for n in names if not n.startswith("aug/rain_jitter_append")]
    arm, spec = _composite_from(cfg, names, "test/all")
    assert arm is not None
    families = {"data/dedup", "data/conf_floor", "data/weight_", "data/hard_neg",
                "data/hard_pos", "data/easy_neg_drop", "aug/rain_jitter_s",
                "aug/gaussian_all", "aug/smote", "loss/focal"}
    for fam in families:
        assert any(s.startswith(fam) for s in spec), f"composite drops family {fam}"


def test_composite_append_jitter_supersedes_inplace_jitter(dc):
    """Both present => the append variant wins and the in-place one is dropped,
    otherwise the same rows get the perturbation applied twice."""
    from sih_ml.train.run_optimize import _composite_from
    _, cfg = dc
    _, spec = _composite_from(
        cfg, ["aug/rain_jitter_append_s0.25", "aug/rain_jitter_s0.1"], "t")
    assert "aug/rain_jitter_append_s0.25" in spec
    assert "aug/rain_jitter_s0.1" not in spec


# --------------------------------------------------------------------------- #
# Reported artifacts stay consistent with the measurements
# --------------------------------------------------------------------------- #
def test_report_verdicts_match_the_decision_rule():
    """Guards against the results JSON and the prose drifting apart."""
    p = REPO_ROOT / "reports" / "stage7" / "optimize_results.json"
    if not p.exists():
        pytest.skip("Stage 7 has not been run")
    R = json.loads(p.read_text())
    for a in R["arms"]:
        d = {"mean_delta": a["mean_delta"], "folds_improved": a["folds_improved"],
             "n_folds": len(a["deltas"]), "p_value": a["p_value"]}
        assert a["verdict"] == verdict(d, 4, 0.10), f"{a['arm']} verdict drifted"


def test_frozen_steps_belong_to_the_selected_scorer():
    """The frozen `composite_steps` must be the steps of the scorer the report says
    was selected.

    This caught a real bug: `composite_spec` was set to whichever composite had the
    highest AP, while `scorer` followed the decision rule. The pre-registration then
    said `composite/passed` but carried the 10 steps of `composite/all_positive` —
    `open_final_test.py` would have trained a different model than the one selected,
    and the discrepancy would only have been visible by diffing two JSON fields.
    """
    p = REPO_ROOT / "reports" / "stage7" / "optimize_results.json"
    if not p.exists():
        pytest.skip("Stage 7 has not been run")
    R = json.loads(p.read_text())
    sel = R["selected_scorer"]
    comps = {c["name"]: c["spec"] for c in R.get("composites", [])}
    if sel in comps:
        assert R["composite_spec"] == comps[sel], (
            f"frozen steps are not {sel}'s steps")
    else:
        assert R["composite_spec"] == [], (
            f"scorer {sel} is not a composite, so no steps should be frozen")

    pre = REPO_ROOT / "reports" / "stage7" / "PREREGISTRATION.json"
    if pre.exists():
        P = json.loads(pre.read_text())
        fc = P["final_config"]
        assert fc["scorer"] == sel
        assert fc["composite_steps"] == R["composite_spec"]
        # the pre-registered dev estimate must be the SELECTED scorer's own CV
        # score — quoting another candidate's makes the dev-vs-test gap meaningless
        de = P["dev_estimate"]
        assert de["scorer"] == sel
        cand = {c["name"]: c["mean_AP"] for c in R.get("composites", [])}
        cand["bar/stage6_tuned"] = R["bar"]["mean_AP"]
        if R.get("ensemble"):
            cand["ensemble"] = R["ensemble"]["mean_AP"]
        assert de["spatial_cv_mean_AP"] == pytest.approx(cand[sel])


def test_selected_scorer_cleared_the_decision_rule():
    """A challenger may only be promoted over the incumbent if its verdict was
    `improvement` — never merely because it posted the highest AP."""
    p = REPO_ROOT / "reports" / "stage7" / "optimize_results.json"
    if not p.exists():
        pytest.skip("Stage 7 has not been run")
    R = json.loads(p.read_text())
    sel = R["selected_scorer"]
    if sel == "bar/stage6_tuned":
        return
    if sel == "ensemble":
        assert R["ensemble"]["verdict"] == "improvement"
        return
    c = next(c for c in R["composites"] if c["name"] == sel)
    assert c["verdict"] == "improvement", f"{sel} was promoted without clearing the rule"
    best_ap = max(x["mean_AP"] for x in R["composites"])
    if c["mean_AP"] < best_ap:
        loser = max(R["composites"], key=lambda x: x["mean_AP"])
        assert loser["verdict"] != "improvement", (
            "a higher-AP candidate also cleared the rule but was not selected")


def test_preregistration_written_before_any_test_opening():
    p = REPO_ROOT / "reports" / "stage7" / "PREREGISTRATION.json"
    if not p.exists():
        pytest.skip("Stage 7 has not been run")
    pre = json.loads(p.read_text())
    for k in ("config_sha256_16", "final_config", "metrics_to_report", "rule"):
        assert k in pre
    ledger = REPO_ROOT / "reports" / "stage7" / "TEST_SET_LEDGER.json"
    if ledger.exists():
        L = json.loads(ledger.read_text())
        # Only openings that could have influenced a choice count against the
        # unbiasedness of the estimate. Stage 8's reporting/robustness reads are
        # recorded as kind="report" and are not selection events.
        decisions = [o for o in L["openings"] if o.get("kind", "decision") == "decision"]
        assert len(decisions) <= 1, (
            f"the locked test set has had {len(decisions)} decision openings — "
            "the reported number is no longer unbiased")
