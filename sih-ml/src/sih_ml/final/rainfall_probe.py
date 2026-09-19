"""Does a genuine rainfall-driven signal exist once leak and confound are removed?

This is the central open question of the remediation pass, so the probe is built to
be answerable rather than suggestive.

Method
------
Out-of-fold, across all 5 spatial folds, with the frozen training recipe: train on a
fold's training rows, score its held-out rows twice — once with observed rainfall,
once with every rainfall input deleted — and take the **paired per-fold difference**.
Repeated over several seeds. Identical protocol to Stage 7's arm ladder, including
the exact sign-flip permutation test, so the result is directly comparable to every
other claim in the project.

The non-circularity rule
------------------------
Positives are stratified by **provenance** (which source recorded the event), never
by rainfall. Splitting them into "wet" and "dry" groups and then showing rainfall
predicts the wet ones would be circular. Provenance is metadata about *who wrote the
label down*, fixed before any rainfall value is looked at:

    inventory  COOLR/GLC — a curated landslide inventory with a recorded trigger
    news       reliefweb + corridor_landslides — scraped from reports
    verified   the 3 hand-verified closures

Each stratum is scored against the SAME full negative set, so the APs are comparable
and the only thing changing is which positives count.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score

from sih_ml.models.dataset import Data
from sih_ml.optimize.augment import ID_EXCEED_COLS, ID_RATIO_COLS, RAIN_COLS
from sih_ml.optimize.harness import Arm, fit_one_fold, paired_delta, verdict
from sih_ml.utils.common import Config, get_logger

log = get_logger("stage9.rain")

PROVENANCE = {
    "coolr_glc": "inventory",
    "corridor_landslides": "news",
    "reliefweb_events": "news",
    "verified_segment_label": "verified",
}

STRATA = ["all", "inventory", "news", "coolr_glc", "corridor_landslides",
          "reliefweb_events", "rain_attributable", "not_rain_attributable"]


def provenance(data: Data) -> np.ndarray:
    return data.panel["label_source"].map(PROVENANCE).fillna("negative").to_numpy()


# Sources whose event DATE cannot be attributed to a rainfall trigger. The boundary
# is PROVENANCE (who recorded the label), fixed before any rainfall value is read.
NOT_RAIN_ATTRIBUTABLE_SOURCES = {"corridor_landslides", "reliefweb_events"}


def trigger_class(data: Data) -> np.ndarray:
    """Split positives by whether their DATE can be attributed to a rainfall trigger.

    The name matters. This is **not** a claim that these disruptions did not happen,
    or that they had no rainfall cause — they are real closures. The claim is
    narrower and is what the evidence supports: *the date on the label is not a
    rainfall-trigger date*, so the antecedent-rainfall window computed from it is
    causally disconnected from the event.

    The class boundary is PROVENANCE, set before any rainfall value is consulted:

        coolr_glc               curated scientific inventory. Per-event triggers with
                                real variation (downpour 80 / rain 40 /
                                continuous_rain 19 / monsoon / flooding /
                                tropical_cyclone / unknown 10).  -> rain_attributable
        corridor_landslides,    news-scraped (reliefweb / gdelt).
        reliefweb_events                                     -> not_rain_attributable

    Why the news sources are separated, in order of evidential weight:

    1. **Their trigger field is a constant.** All 26 corridor rows read
       `rainfall_or_flood`; all 4 reliefweb rows read `unknown`. A column with one
       value is a pipeline default, not a per-event attribution, so it carries no
       information about any individual event. (An earlier draft of this module
       treated `rainfall_or_flood` as a recorded rainfall attribution. That was
       wrong, and the constant-column check is what caught it.)
    2. **Location accuracy is `place_level` for every row** (+/-15 km), against
       COOLR's 100 m - 25 km range with real variation.
    3. **The date-lag hypothesis is refuted by measurement.** If a news date lagged a
       real rainfall trigger, a LONGER antecedent window would recover the signal.
       Measured ROC by window, positives-of-source vs all negatives:

           coolr_glc            1d .597  3d .651  7d .659  15d .653  30d .650
           corridor_landslides  1d .508  3d .505  7d .466  15d .419  30d .402
           reliefweb_events     1d .314  3d .198  7d .166  15d .254  30d .298

       COOLR rises to a peak at 7 days and plateaus — the physical antecedent-
       rainfall signature. The news sources get monotonically *worse* as the window
       lengthens, which is the opposite of a lag.
    4. **They are drier than the negative sample at every window** (7-day median
       29.8 mm for corridor vs 49.6 mm for negatives). Negatives are season-matched
       and include a matched hard-negative donut, so they sit on rainy days by
       construction; positives that are drier than that are not trigger-day rows.

    Together these are consistent with news reports capturing **ongoing closures and
    aftermath** rather than trigger days — NH-10 closures after the October 2023
    Teesta flooding persisted for months — for which no 30-day antecedent window can
    contain the cause.

    Points 3 and 4 do consult rainfall, and that is not circular: the class boundary
    is provenance, decided independently. Rainfall behaviour is used to *explain* the
    split, never to define it.
    """
    src = data.panel["label_source"].astype(str).to_numpy()
    out = np.where(data.y == 1, "rain_attributable", "negative").astype(object)
    out[(data.y == 1) & np.isin(src, list(NOT_RAIN_ATTRIBUTABLE_SOURCES))] = "not_rain_attributable"
    return out


def scope_mask(data: Data) -> np.ndarray:
    """Rows the rainfall model is scoped to: every negative, plus every positive whose
    date can be attributed to a rainfall trigger.

    Out-of-scope positives are NOT deleted from the dataset. They stay in the panel,
    are reported as their own named slice, and remain the product's problem — they
    are simply not something a rainfall-feature model can predict, and including them
    in its target caps achievable performance while corrupting the evaluation.
    """
    return trigger_class(data) != "not_rain_attributable"


def strip_rainfall(X: pd.DataFrame, ref: pd.DataFrame | None = None) -> pd.DataFrame:
    """Delete every rainfall input. `days_since_rain` is pinned to its maximum so the
    row reads as 'no recent rain' rather than as a missing value."""
    X = X.copy()
    ref = ref if ref is not None else X
    for c in RAIN_COLS + ID_RATIO_COLS:
        if c in X:
            X[c] = 0.0
    for c in ID_EXCEED_COLS:
        if c in X:
            X[c] = 0
    if "days_since_rain" in X:
        X["days_since_rain"] = float(np.nanmax(ref["days_since_rain"].to_numpy(float)))
    return X


def _ap_by_stratum(y: np.ndarray, p: np.ndarray, fam: dict) -> dict:
    """AP for each positive stratum, every one scored against the SAME negatives so
    the numbers are comparable across strata."""
    out = {}
    neg = y == 0
    for s in STRATA:
        if s == "all":
            keep = np.ones(len(y), bool)
        else:
            member = (fam["prov"] == s) | (fam["src"] == s) | (fam["trig"] == s)
            keep = neg | ((y == 1) & member)
        yy, pp = y[keep], p[keep]
        if yy.sum() < 5:
            continue
        out[s] = {
            "n_pos": int(yy.sum()), "base_rate": float(yy.mean()),
            "AP": float(average_precision_score(yy, pp)),
            "AP_over_base": float(average_precision_score(yy, pp) / yy.mean()),
            "roc_auc": float(roc_auc_score(yy, pp)) if 0 < yy.sum() < len(yy) else np.nan,
        }
    return out


def rainfall_ablation_cv(data: Data, cfg: Config, folds: list[int], seeds: list[int]) -> dict:
    """Paired out-of-fold rainfall ablation, stratified by provenance, over seeds."""
    # one label array carrying every stratum key a row belongs to is impossible, so
    # score each family in turn against the same predictions
    prov_family = provenance(data)
    src_family = data.panel["label_source"].astype(str).to_numpy()
    trig_family = trigger_class(data)
    per_seed, rows = {}, []

    def strat_for(idx):
        """Resolve the stratum label for each row, preferring the most specific."""
        return {"prov": prov_family[idx], "src": src_family[idx], "trig": trig_family[idx]}

    for seed in seeds:
        obs = np.full(len(data.panel), np.nan)
        dry = np.full(len(data.panel), np.nan)
        fold_of = np.full(len(data.panel), -1)
        arm = Arm("frozen_recipe", "baseline", _recipe_transform(cfg))
        for f in folds:
            ap, va, pred, model, _, _ = fit_one_fold(data, cfg, arm, f, seed)
            obs[va] = pred
            dry[va] = model.predict(strip_rainfall(data.X(va)))
            fold_of[va] = f

        fold_obs, fold_dry = {}, {}
        for f in folds:
            idx = np.where(fold_of == f)[0]
            y, fam = data.y[idx], strat_for(idx)
            fold_obs[f] = _ap_by_stratum(y, obs[idx], fam)
            fold_dry[f] = _ap_by_stratum(y, dry[idx], fam)

        for s in STRATA:
            if s not in fold_obs[folds[0]]:
                continue
            a = {"fold_ap": {f: fold_obs[f][s]["AP"] for f in folds if s in fold_obs[f]}}
            b = {"fold_ap": {f: fold_dry[f][s]["AP"] for f in folds if s in fold_dry[f]}}
            ff = sorted(a["fold_ap"])
            # delta = observed MINUS dry, so positive => rainfall HELPS
            d = paired_delta(a, b, ff, 20000, seed)
            rows.append({
                "seed": seed, "stratum": s,
                "AP_observed": float(np.nanmean(list(a["fold_ap"].values()))),
                "AP_rain_deleted": float(np.nanmean(list(b["fold_ap"].values()))),
                "delta_rain_helps": d["mean_delta"], "p_value": d["p_value"],
                "folds_rain_helps": d["folds_improved"], "n_folds": d["n_folds"],
                "verdict": verdict(d, 4, 0.10),
                "deltas": d["deltas"],
            })
        per_seed[seed] = {"observed": fold_obs, "rain_deleted": fold_dry}

    df = pd.DataFrame(rows)
    summary = []
    for s, g in df.groupby("stratum"):
        all_d = [x for row in g.deltas for x in row]
        summary.append({
            "stratum": s,
            "n_seeds": int(g.seed.nunique()),
            "mean_AP_observed": float(g.AP_observed.mean()),
            "mean_AP_rain_deleted": float(g.AP_rain_deleted.mean()),
            "mean_delta_rain_helps": float(g.delta_rain_helps.mean()),
            "fold_seed_pairs_rain_helps": int(np.sum(np.array(all_d) > 0)),
            "fold_seed_pairs": len(all_d),
            "replicated_all_seeds": bool((g.delta_rain_helps > 0).all()),
            "per_seed_verdicts": g.verdict.tolist(),
        })
    return {"per_seed_rows": rows, "summary": summary, "detail": per_seed}


def _recipe_transform(cfg: Config):
    """The frozen Stage 7 training recipe, rebuilt from the config's composite steps."""
    steps = list(cfg.get("remediate", {}).get("composite_steps", []))
    if not steps:
        return None
    from sih_ml.train.run_optimize import _composite_from
    arm, _ = _composite_from(cfg, steps, "recipe")
    return arm.transform if arm else None
