"""Scoring: raw booster output -> calibrated probability -> rank -> alert tier.

The output contract follows the Stage 9 deployment recommendation, not convenience:

  * `risk_percentile` (rank among all corridor segments that day) is the PRIMARY
    output. The ranking is what the evidence supports on new terrain.
  * `p_calibrated` is returned but labelled: it is calibrated on a case-control
    panel (~10 negatives per positive), so its absolute level overstates the true
    daily probability on the full corridor, and Stage 9 measured it NOT transferring
    across regions (worst terrain stratum 2.65x). It must not drive the routing
    penalty W = dist * (1 + lambda * P) on unseen ground without local recalibration.
  * `tier`: steep segments (slope >= 10 deg) above threshold go to HUMAN REVIEW, never
    to autonomous alerting — Stage 9 measured steep ROC ~0.75 in known regions and
    0.63 in a new one.
"""
from __future__ import annotations

import numpy as np

from sih_ml.serve.bundle import Bundle
from sih_ml.serve.validate import check_output

TIER_NONE, TIER_ALERT, TIER_REVIEW = "none", "alert", "human_review"


class Predictor:
    def __init__(self, bundle: Bundle, num_threads: int = 0):
        self.bundle = bundle
        self.booster = bundle.booster
        self.num_threads = int(num_threads)
        pol = bundle.policy
        self.threshold = float(pol["alert_probability_threshold"])
        self.steep_deg = float(pol["steep_slope_deg"])

    def raw(self, X: np.ndarray) -> np.ndarray:
        return self.booster.predict(X, num_threads=self.num_threads)

    def tiers(self, prob: np.ndarray, slope: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        steep = np.nan_to_num(slope, nan=0.0) >= self.steep_deg
        hit = prob >= self.threshold
        tier = np.where(hit & steep, TIER_REVIEW, np.where(hit, TIER_ALERT, TIER_NONE))
        return tier, steep

    def score(self, X: np.ndarray, slope: np.ndarray) -> dict[str, np.ndarray]:
        raw = self.raw(X)
        prob = self.bundle.calibration(raw, slope)
        check_output(prob, raw)
        tier, steep = self.tiers(prob, slope)
        return {"raw_score": raw, "p_calibrated": prob, "steep": steep, "tier": tier}


def percentile_rank(raw: np.ndarray) -> np.ndarray:
    """0-100, higher = riskier; ties share the average rank."""
    order = raw.argsort(kind="stable")
    ranks = np.empty(len(raw))
    ranks[order] = np.arange(1, len(raw) + 1)
    # average ties so equal scores get equal percentiles
    uniq, inv, counts = np.unique(raw, return_inverse=True, return_counts=True)
    if len(uniq) < len(raw):
        sums = np.bincount(inv, weights=ranks)
        ranks = (sums / counts)[inv]
    return 100.0 * ranks / len(raw)


def percentile_against(raw: np.ndarray, reference_sorted: np.ndarray) -> np.ndarray:
    """Percentile of new scores within a day's already-scored corridor distribution."""
    return 100.0 * np.searchsorted(reference_sorted, raw, side="right") / len(reference_sorted)
