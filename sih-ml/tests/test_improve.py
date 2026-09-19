"""Stage 10 contract tests — the loop's rules, pinned so they cannot drift.

Two groups: rule tests that need no training run (fast, always on), and artifact
tests that check a finished campaign against those same rules (skipped until
`make stage10` has produced reports/stage10/).
"""
from __future__ import annotations

import json
import re

import numpy as np
import pandas as pd
import pytest

from sih_ml.improve import candidate as C
from sih_ml.improve import decide as Dc
from sih_ml.utils.common import REPO_ROOT, load_config_with_base

CFG = REPO_ROOT / "conf" / "improve_config.yaml"
S10 = REPO_ROOT / "reports" / "stage10"
LEDGER = S10 / "EXPERIMENT_LEDGER.jsonl"


@pytest.fixture(scope="module")
def icfg():
    return load_config_with_base(CFG)


# ------------------------------------------------------------- the locked split
def test_stage10_code_never_references_the_locked_split():
    """Every decision in the loop is made on dev data. The only sanctioned exclusion
    is Data.dev_mask(); nothing in Stage 10 may name the locked split directly."""
    files = [*sorted((REPO_ROOT / "src" / "sih_ml" / "improve").glob("*.py")),
             REPO_ROOT / "src" / "sih_ml" / "train" / "run_improve.py",
             REPO_ROOT / "scripts" / "run_stage10.py"]
    for p in files:
        src = p.read_text()
        assert not re.search(r"final_test|open_final_test|TEST_SET_LEDGER", src), p.name


def test_stage10_did_not_open_the_locked_split():
    led = json.loads((REPO_ROOT / "reports" / "stage7" / "TEST_SET_LEDGER.json").read_text())
    for o in led["openings"]:
        assert "final_v3" not in json.dumps(o) and "stage 10" not in json.dumps(o).lower()


# ------------------------------------------------------------ one variable
def test_every_backlog_experiment_changes_exactly_one_thing(icfg):
    s0 = C.initial_state(icfg)
    for e in icfg.improve.experiments:
        assert len(e["change"]) == 1, e["id"]
        s1 = C.apply_change(s0, dict(e["change"]))
        diff = [k for k in C.KNOWN_KEYS if s1[k] != s0[k]]
        assert len(diff) == 1, (e["id"], diff)
        if diff == ["composite_steps"]:
            assert len(set(s1["composite_steps"]) ^ set(s0["composite_steps"])) == 1


def test_apply_change_refuses_multi_variable_changes(icfg):
    s0 = C.initial_state(icfg)
    with pytest.raises(ValueError):
        C.apply_change(s0, {"bag": 3, "coverage_mask": True})
    with pytest.raises(ValueError):
        C.apply_change(s0, {"lgbm": {"num_leaves": 8, "learning_rate": 0.1}})
    with pytest.raises(ValueError):
        C.apply_change(s0, {"remove_step": "not/a_step"})


def test_every_experiment_declares_its_evidence_and_bottleneck(icfg):
    names = set(icfg.improve.bottlenecks)
    for e in icfg.improve.experiments:
        assert e["kind"] in ("correctness", "superiority", "simplification")
        assert e["bottleneck"] in names, e["id"]
        assert e["hypothesis"].strip() and e["evidence"].strip(), e["id"]


def test_max_bin_passthrough_is_inert_for_earlier_configs():
    """Stages 3-9 must train bit-identically: the new param only appears when set."""
    from sih_ml.models.lgbm_baseline import LGBMBaseline
    p = {"learning_rate": .1, "num_leaves": 4, "max_depth": 3, "min_child_samples": 5,
         "subsample": 1, "subsample_freq": 0, "colsample_bytree": 1, "reg_alpha": 0,
         "reg_lambda": 0}
    assert "max_bin_by_feature" not in LGBMBaseline(p, ["a"], [])._lgb_params(None)


# ---------------------------------------------------------------- the rules
def _cmp(D):
    return Dc.compare(np.asarray(D, float), [0, 1, 2, 3, 4], 4, 0.10)


NOISE = {"delta_floor": 0.004, "worst_fold_floor": 0.02}


def test_superiority_requires_all_folds_all_seeds_and_the_noise_floor():
    good = _cmp([[.01, .02, .01, .03, .02]] * 3)
    assert Dc.decide("superiority", good, [], NOISE)[0] == Dc.ACCEPT
    four_of_five = _cmp([[.01, .02, .01, .03, -.001]] * 3)
    assert Dc.decide("superiority", four_of_five, [], NOISE)[0] == Dc.NOT_DEMONSTRATED
    tiny = _cmp([[.001, .002, .001, .003, .002]] * 3)
    assert Dc.decide("superiority", tiny, [], NOISE)[0] == Dc.NOT_DEMONSTRATED
    one_seed_down = _cmp([[.01] * 5, [.01] * 5, [-.001] * 5])
    assert Dc.decide("superiority", one_seed_down, [], NOISE)[0] == Dc.NOT_DEMONSTRATED
    assert Dc.decide("superiority", good, ["steep terrain"], NOISE)[0] == Dc.REJECT


def test_simplification_margin_is_capped_even_under_a_wide_noise_floor():
    loss = _cmp([[-.02, -.01, .005, -.03, .002]] * 3)
    wide = {"delta_floor": 0.05, "worst_fold_floor": 0.05}
    assert Dc.decide("simplification", loss, [], wide, ni_margin_cap=0.01)[0] == Dc.REJECT
    neutral = _cmp([[.001, -.002, .002, -.001, .0]] * 3)
    assert Dc.decide("simplification", neutral, [], NOISE, 0.01)[0] == Dc.ACCEPT
    mostly_worse = _cmp([[-.001, -.002, -.001, -.001, .001]] * 3)
    assert Dc.decide("simplification", mostly_worse, [], NOISE, 0.01)[0] == Dc.REJECT


def test_correctness_fix_is_adopted_unless_it_regresses():
    flat = _cmp([[.001, -.001, .0, .002, -.002]] * 3)
    assert Dc.decide("correctness", flat, [], NOISE)[0] == Dc.ACCEPT
    worse = _cmp([[-.01, -.02, -.01, -.03, -.02]] * 3)
    assert Dc.decide("correctness", worse, [], NOISE)[0] == Dc.REJECT


def test_guardrails_use_the_larger_of_config_and_aa_floor():
    lim = {"max_steep_roc_drop": 0.01, "max_worst_terrain_cal_ratio": 1.5,
           "max_cal_ratio_increase": 0.25, "max_monotonicity_violations": 0,
           "max_corridor_sec": 300, "max_model_mb": 50}
    base = {"steep_roc": 0.75, "worst_terrain_cal_ratio": 1.10, "monotonicity_violations": 0,
            "corridor_sec": 1, "model_mb": 1}
    cmp = _cmp([[.0] * 5] * 3)
    noisy = {**NOISE, "steep_roc_floor": 0.02, "cal_ratio_floor": 0.1}
    ch = {**base, "steep_roc": 0.735}                   # -0.015: inside the A/A floor
    assert Dc.guardrail_failures(ch, base, cmp, noisy, lim) == []
    assert Dc.guardrail_failures(ch, base, cmp, NOISE, lim)   # outside the 0.01 minimum
    crosses = {**base, "worst_terrain_cal_ratio": 1.52}
    b2 = {**base, "worst_terrain_cal_ratio": 1.45}
    assert any("gate" in f for f in Dc.guardrail_failures(crosses, b2, cmp, NOISE, lim))
    assert Dc.guardrail_failures({**base, "monotonicity_violations": 1}, base, cmp, NOISE, lim)


def test_aa_noise_of_identical_runs_is_zero():
    ap = {s: {f: 0.4 + 0.01 * f for f in range(5)} for s in range(6)}
    n = Dc.aa_noise(ap, list(range(6)), list(range(5)), 0.9, 4, 0.10)
    assert n["n_splits"] == 20 and n["delta_floor"] == 0 and n["old_rule_false_positive_rate"] == 0


# ------------------------------------------------------------ data integrity
def test_rainfall_builder_no_longer_snaps_past_the_record():
    from sih_ml.features.rainfall import rainfall_features
    idx = pd.date_range("2025-12-01", "2025-12-31")
    series = pd.DataFrame({"c1": np.ones(len(idx))}, index=idx)
    seg_cell = pd.DataFrame({"segment_id": ["s"], "cell_id": ["c1"]})
    pairs = pd.DataFrame({"segment_id": ["s", "s"],
                          "date": pd.to_datetime(["2025-12-20", "2026-07-15"])})
    out = rainfall_features(pairs, series, seg_cell, 1)
    assert out.loc[0, "rain_7d_mm"] == 7.0
    assert np.isnan(out.loc[1, "rain_7d_mm"]) and np.isnan(out.loc[1, "api_mm"])


def test_panel_v1_defect_is_pinned_and_masked(icfg):
    """panel_v1 is not rebuilt in Stage 10; the defect is corrected by the coverage
    mask. If a rebuild removes the rows, this fails and the D1 write-up must be revisited."""
    from sih_ml.improve.features import coverage_mask
    from sih_ml.models.dataset import load_data
    data, cfg = load_data(CFG)
    cov = coverage_mask(data, cfg)
    beyond = ~cov
    dev = data.dev_mask()
    assert (pd.to_datetime(data.panel.date[beyond]).dt.year == 2026).all()
    assert int((beyond & dev).sum()) > 4000 and int(data.y[beyond & dev].sum()) == 0
    r7 = data.panel["rain_7d_mm"].to_numpy(float)
    assert np.nanmedian(r7[beyond & dev]) < 1.0 < np.nanmedian(r7[cov & dev])


def test_local_percentiles_are_monotone_in_rainfall(icfg):
    from sih_ml.improve.features import LocalRainPercentiles
    lp = LocalRainPercentiles(icfg)
    cell = next(iter(lp.cdf))[0]
    rain = np.linspace(0, 400, 200)
    p = lp.percentiles(rain, np.array([cell] * len(rain)), 7)
    assert np.all(np.diff(p) >= 0) and p[0] >= 0 and p[-1] <= 1


# ------------------------------------------------------ the finished campaign
def _last_campaign():
    if not LEDGER.exists():
        pytest.skip("run `make stage10` first")
    rows = [json.loads(x) for x in LEDGER.read_text().splitlines() if x.strip()]
    cid = [r["campaign_id"] for r in rows if "campaign_id" in r][-1]
    return [r for r in rows if r.get("campaign_id") == cid]


def test_campaign_reproduced_the_champion_before_comparing():
    rep = [r for r in _last_campaign() if r["type"] == "reproduction"]
    assert rep and rep[0]["ok"] and rep[0]["per_seed_AP_match"] and rep[0]["dev_threshold_match"]


def test_every_experiment_is_fully_recorded():
    exps = [r for r in _last_campaign() if r["type"] == "experiment"]
    assert exps
    for e in exps:
        for k in ("hypothesis", "evidence", "change", "decision", "reason", "fingerprint",
                  "ap_champion", "ap_challenger", "champion_state_sha16", "guardrails"):
            assert e.get(k) not in (None, "", {}), (e["name"], k)
        assert e["fingerprint"]["code_sha16"] and e["fingerprint"]["data_sha16"]


def test_published_decisions_follow_the_rule(icfg):
    """Recompute every decision from the raw per-(seed, fold) AP in the ledger."""
    cap = float(icfg.improve.ni_margin_cap)
    for e in [r for r in _last_campaign() if r["type"] == "experiment"]:
        ap_c = {int(s): {int(f): v for f, v in d.items()} for s, d in e["ap_challenger"].items()}
        ap_b = {int(s): {int(f): v for f, v in d.items()} for s, d in e["ap_champion"].items()}
        D = Dc.delta_table(ap_c, ap_b, e["seeds"], e["seeds"], e["folds"])
        cmp = Dc.compare(D, e["folds"], int(icfg.improve.min_folds_improved),
                         float(icfg.improve.alpha))
        noise = {"delta_floor": e["noise_floor"], "worst_fold_floor": e["worst_fold_floor"]}
        dec, _ = Dc.decide(e["kind"], cmp, e["guardrails"]["failures"], noise, cap)
        assert dec == e["decision"], e["name"]
        assert abs(cmp["mean_delta"] - e["comparison"]["mean_delta"]) < 1e-12


def test_registry_lineage_matches_accepted_experiments():
    reg = json.loads((REPO_ROOT / "models" / "registry.json").read_text())
    accepted = {r["id"] for r in _last_campaign()
                if r["type"] == "experiment" and r["decision"] == Dc.ACCEPT}
    assert set(reg["last_campaign"]["accepted"]) <= accepted
    versions = {v["version"]: v for v in reg["versions"]}
    assert versions["final_v1"]["status"].startswith("known-leaked")
    assert reg["champion"] in versions
    champ = versions[reg["champion"]]
    if reg["champion"] != "final_v2":
        assert "NOT opened" in champ["locked_split"] and reg["champion_reason"]
        assert (REPO_ROOT / champ["artifact"] / "model_card.json").exists()
