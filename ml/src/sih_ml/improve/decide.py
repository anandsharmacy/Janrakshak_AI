"""Keep / revert decisions — pure functions over per-(seed, fold) AP tables.

Three experiment kinds, three rules
-----------------------------------
correctness     A fix for something that is WRONG (a data bug, an escaped constraint).
                Adopted on correctness grounds unless it causes a demonstrated
                regression or breaks a guardrail. Stage 9's monotonicity fix is the
                precedent: adopted at "not demonstrated" accuracy impact.
superiority     A change claimed to make the model better. ALL of:
                  * Stage 7/9 rule on fold-averaged deltas: mean > 0, >= 4/5 folds,
                    exact sign-flip p < 0.10;
                  * replicated: mean delta > 0 under EVERY seed;
                  * practically significant: mean delta > the A/A noise floor;
                  * no guardrail breached.
simplification  A change that REMOVES a component. Accepted if non-inferior: mean
                delta >= -margin with margin = min(A/A floor, ni_margin_cap), not a
                demonstrated regression, fewer than 4/5 folds worse, and at most one
                seed below -margin. Removing a component that does nothing is an
                improvement in its own right (fewer moving parts, less variance), and
                demanding superiority for it would keep dead weight forever.

Guardrails have their own A/A floors (steep ROC, terrain calibration), so a guardrail
fires only when a metric moves further than seed noise moves it.

The A/A noise floor
-------------------
The champion is trained under 2 x 3 seeds. Every way of splitting those 6 seeds into
two groups of 3 is an A/A comparison of the model against ITSELF — any delta it shows
is pure seed noise (ES split, bagging RNG, augmentation noise). The floor is the
`q`-quantile of |mean delta| over those splits, and the same splits give the
worst-fold floor used by the region guardrail and the empirical false-positive rate
of the Stage 7/9 rule. Different seeds on both sides make this a slightly
conservative null for a same-seed paired comparison; that is the right direction to
err in.
"""
from __future__ import annotations

from itertools import combinations

import numpy as np

from sih_ml.optimize.harness import paired_delta, verdict

ACCEPT, REJECT, NOT_DEMONSTRATED = "ACCEPT", "REJECT", "NOT DEMONSTRATED"


def delta_table(ch_ap: dict, base_ap: dict, seeds_ch: list, seeds_base: list,
                folds: list[int]) -> np.ndarray:
    """seeds x folds matrix of challenger - base AP, seeds paired by position."""
    return np.array([[ch_ap[sc][f] - base_ap[sb][f] for f in folds]
                     for sc, sb in zip(seeds_ch, seeds_base)], float)


def compare(D: np.ndarray, folds: list[int], min_folds: int, alpha: float,
            n_perm: int = 20000) -> dict:
    fold_avg = np.nanmean(D, axis=0)
    prim = paired_delta({"fold_ap": dict(zip(folds, fold_avg))},
                        {"fold_ap": {f: 0.0 for f in folds}}, folds, n_perm)
    per_seed = []
    for row in D:
        d = paired_delta({"fold_ap": dict(zip(folds, row))},
                         {"fold_ap": {f: 0.0 for f in folds}}, folds, n_perm)
        per_seed.append({"mean_delta": d["mean_delta"], "p_value": d["p_value"],
                         "folds_improved": d["folds_improved"],
                         "verdict": verdict(d, min_folds, alpha)})
    return {
        "mean_delta": float(np.nanmean(D)),
        "fold_avg_deltas": [float(x) for x in fold_avg],
        "worst_fold_delta": float(np.nanmin(fold_avg)),
        "p_value": prim["p_value"],
        "folds_improved": prim["folds_improved"],
        "n_folds": len(folds),
        "verdict": verdict(prim, min_folds, alpha),
        "per_seed": per_seed,
        "seeds_positive": int(sum(r["mean_delta"] > 0 for r in per_seed)),
        "n_seeds": len(per_seed),
        "pairs_improved": int(np.sum(D > 0)),
        "n_pairs": int(np.isfinite(D).sum()),
        "deltas": D.tolist(),
    }


def _half_splits(seeds: list):
    k = len(seeds) // 2
    for A in combinations(seeds, k):
        B = [s for s in seeds if s not in A]
        if tuple(B) < A:                       # each unordered split once
            continue
        yield list(A), B


def aa_metric_floor(per_seed: dict, seeds: list, q: float) -> float:
    """A/A floor for a scalar guardrail metric: q-quantile over the half-splits of
    |mean(B) - mean(A)|, i.e. how far the metric moves between two 3-seed averages of
    the SAME model."""
    d = [abs(np.mean([per_seed[s] for s in B]) - np.mean([per_seed[s] for s in A]))
         for A, B in _half_splits(seeds)]
    return float(np.quantile(d, q))


def aa_noise(ap: dict, seeds: list, folds: list[int], q: float,
             min_folds: int, alpha: float, metrics: dict | None = None) -> dict:
    """A/A calibration from the champion trained under len(seeds) (even) seeds.
    `metrics` = {name: {seed: value}} for guardrail metrics that get their own floor."""
    splits = []
    for A, B in _half_splits(seeds):
        A = tuple(A)
        for a, b in ((list(A), B), (B, list(A))):   # both orientations for FP rate
            D = delta_table(ap, ap, b, a, folds)
            c = compare(D, folds, min_folds, alpha)
            splits.append({"a": a, "b": b, "mean_delta": c["mean_delta"],
                           "worst_fold_delta": c["worst_fold_delta"],
                           "verdict": c["verdict"], "seeds_positive": c["seeds_positive"]})
    md = np.array([abs(s["mean_delta"]) for s in splits])
    wf = np.array([max(0.0, -s["worst_fold_delta"]) for s in splits])
    # How often the Stage 7/9 rule alone calls a model "better than itself". (The
    # same number for the new rule is not reported: its floor is fitted on these very
    # splits, so its in-sample false-positive rate is <= 1-q by construction.)
    old_rule_fp = float(np.mean([s["verdict"] == "improvement" for s in splits]))
    out = {"n_splits": len(splits), "quantile": q,
           "delta_floor": float(np.quantile(md, q)),
           "worst_fold_floor": float(np.quantile(wf, q)),
           "max_abs_mean_delta": float(md.max()),
           "old_rule_false_positive_rate": old_rule_fp,
           "splits": splits}
    for name, per_seed in (metrics or {}).items():
        out[f"{name}_floor"] = aa_metric_floor(per_seed, seeds, q)
        out[f"{name}_per_seed"] = {str(s): float(v) for s, v in per_seed.items()}
    return out


# --------------------------------------------------------------------------- #
def guardrail_failures(g_ch: dict, g_base: dict, cmp: dict, noise: dict, lim: dict) -> list[str]:
    """Everything that must hold regardless of AP. Returns human-readable failures."""
    out = []
    if cmp["worst_fold_delta"] < -noise["worst_fold_floor"]:
        out.append(f"region: worst fold {cmp['worst_fold_delta']:+.4f} AP, beyond the A/A "
                   f"worst-fold floor -{noise['worst_fold_floor']:.4f}")
    # Each tolerance is the configured minimum OR the metric's own A/A floor, whichever
    # is larger — a guardrail must not fire on seed noise any more than an AP claim may.
    d_steep = g_ch["steep_roc"] - g_base["steep_roc"]
    steep_tol = max(float(lim["max_steep_roc_drop"]), noise.get("steep_roc_floor", 0.0))
    if d_steep < -steep_tol:
        out.append(f"steep terrain: ROC {d_steep:+.4f} (tolerance -{steep_tol:.4f})")
    cal, cal0 = g_ch["worst_terrain_cal_ratio"], g_base["worst_terrain_cal_ratio"]
    cal_tol = max(float(lim["max_cal_ratio_increase"]), noise.get("cal_ratio_floor", 0.0))
    gate = float(lim["max_worst_terrain_cal_ratio"])
    if cal - cal0 > cal_tol:
        out.append(f"calibration: worst terrain stratum {cal:.2f}x vs champion {cal0:.2f}x "
                   f"(tolerance +{cal_tol:.2f})")
    elif cal > gate >= cal0:
        out.append(f"calibration: worst terrain stratum {cal:.2f}x crosses the {gate}x "
                   f"deployment gate the champion passes ({cal0:.2f}x)")
    if g_ch["monotonicity_violations"] > int(lim["max_monotonicity_violations"]):
        out.append(f"monotonicity: {g_ch['monotonicity_violations']} violations")
    if g_ch["corridor_sec"] > float(lim["max_corridor_sec"]):
        out.append(f"latency: {g_ch['corridor_sec']:.1f}s for the corridor")
    if g_ch["model_mb"] > float(lim["max_model_mb"]):
        out.append(f"size: {g_ch['model_mb']:.1f} MB")
    return out


def decide(kind: str, cmp: dict, guard_fail: list[str], noise: dict,
           ni_margin_cap: float = 0.01) -> tuple[str, str]:
    floor = noise["delta_floor"]
    if kind == "correctness":
        if guard_fail:
            return REJECT, "correctness fix breaks a guardrail: " + "; ".join(guard_fail)
        if cmp["verdict"] == "regression":
            return REJECT, "correctness fix causes a demonstrated regression — investigate"
        return ACCEPT, ("correctness fix adopted on correctness grounds; accuracy effect "
                        f"{cmp['mean_delta']:+.4f} ({cmp['verdict']}), no guardrail breached")

    if kind == "superiority":
        if guard_fail:
            return REJECT, "guardrail: " + "; ".join(guard_fail)
        if cmp["verdict"] == "regression":
            return REJECT, f"demonstrated regression ({cmp['mean_delta']:+.4f})"
        unmet = []
        if cmp["verdict"] != "improvement":
            unmet.append(f"decision rule not met ({cmp['folds_improved']}/{cmp['n_folds']} folds, "
                         f"p={cmp['p_value']:.3f})")
        if cmp["seeds_positive"] < cmp["n_seeds"]:
            unmet.append(f"not replicated ({cmp['seeds_positive']}/{cmp['n_seeds']} seeds)")
        if cmp["mean_delta"] <= floor:
            unmet.append(f"inside A/A noise ({cmp['mean_delta']:+.4f} <= {floor:.4f})")
        if unmet:
            return NOT_DEMONSTRATED, "; ".join(unmet)
        return ACCEPT, (f"improvement {cmp['mean_delta']:+.4f} AP, "
                        f"{cmp['folds_improved']}/{cmp['n_folds']} folds, "
                        f"{cmp['n_seeds']}/{cmp['n_seeds']} seeds, above A/A floor {floor:.4f}")

    if kind == "simplification":
        # The margin is the A/A floor, CAPPED: a wide noise floor must not license
        # throwing away a component that costs real accuracy. The smoke run that
        # motivated the cap accepted a -0.020 removal against a 2-split floor of 0.039.
        margin = min(floor, ni_margin_cap)
        if guard_fail:
            return REJECT, "removal breaks a guardrail: " + "; ".join(guard_fail)
        below = sum(r["mean_delta"] < -margin for r in cmp["per_seed"])
        folds_worse = int(sum(d < 0 for d in cmp["fold_avg_deltas"]))
        if (cmp["verdict"] == "regression" or cmp["mean_delta"] < -margin or below >= 2
                or folds_worse >= cmp["n_folds"] - 1):
            return REJECT, (f"component still earns its place: removing it costs "
                            f"{cmp['mean_delta']:+.4f} AP (margin {margin:.4f}; "
                            f"{folds_worse}/{cmp['n_folds']} folds worse, {below}/{cmp['n_seeds']} seeds "
                            f"below the margin)")
        return ACCEPT, (f"non-inferior ({cmp['mean_delta']:+.4f} AP, margin {margin:.4f}, "
                        f"{folds_worse}/{cmp['n_folds']} folds worse) — fewer moving parts for the same accuracy")
    raise ValueError(kind)


def rank_accepted(items: list[dict]) -> list[dict]:
    """Order for greedy composition: simplifications first (they shrink the model),
    then superiority by effect size. Correctness fixes are applied before round 1."""
    return sorted(items, key=lambda e: (e["kind"] != "simplification", -e["mean_delta"]))
