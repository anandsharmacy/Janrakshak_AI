"""Custom training objectives for Stage 7 (brief §3: "test suitable loss functions").

Only ONE alternative objective is implemented — **binary focal loss** — because it
is the only one with a measured reason to be tried here. Stage 5 §3 found that the
positives we miss are systematically the low-rainfall ones, i.e. the hard examples;
focal loss is precisely the loss that down-weights easy examples and concentrates
gradient on hard ones. Everything else on the usual list (hinge, MSE, ranking
losses) has no such motivation in the error analysis and would be cargo-culting.

Two implementation details that are easy to get wrong
-----------------------------------------------------
1. **LightGBM does not apply `sample_weight` to a custom objective.** For built-in
   objectives the weights are folded in by the C++ side, but a Python `fobj`
   receives raw gradients and must multiply by `dataset.get_weight()` itself.
   Forgetting this silently discards the Stage 2 label-confidence weights.
2. **`scale_pos_weight` has no effect on a custom objective** either. Class
   imbalance is carried by focal `alpha` instead, so the harness passes
   `scale_pos_weight=None` whenever an objective is supplied.
"""
from __future__ import annotations

import numpy as np


def _sigmoid(z: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(z, -50.0, 50.0)))


def _focal_grad(z: np.ndarray, y: np.ndarray, gamma: float, alpha: float) -> np.ndarray:
    """dL/dz for L = -a_t (1 - p_t)^gamma log(p_t).

    With p = sigmoid(z), p_t = y*p + (1-y)*(1-p) and s = 2y-1:
        dp_t/dz = s * p * (1 - p)
        dL/dp_t = a_t * [ gamma * (1-p_t)^(gamma-1) * log(p_t) - (1-p_t)^gamma / p_t ]
    """
    p = _sigmoid(z)
    s = 2.0 * y - 1.0
    pt = np.clip(y * p + (1.0 - y) * (1.0 - p), 1e-9, 1.0 - 1e-9)
    at = alpha * y + (1.0 - alpha) * (1.0 - y)
    dL_dpt = at * (gamma * (1.0 - pt) ** (gamma - 1.0) * np.log(pt)
                   - (1.0 - pt) ** gamma / pt)
    return dL_dpt * s * p * (1.0 - p)


def make_focal_objective(gamma: float = 2.0, alpha: float = 0.25, eps: float = 1e-5):
    """Return a LightGBM `fobj` closure: (preds, Dataset) -> (grad, hess).

    The Hessian is taken as a central finite difference of the analytic gradient.
    The exact second derivative of focal loss is long and its sign is not
    guaranteed positive, which makes LightGBM's leaf update unstable; the
    finite-difference form costs two extra sigmoid evaluations and is then clipped
    strictly positive, which is the standard remedy. `eps=1e-5` sits comfortably
    inside float64 precision for the |z| <= 50 range we clip to.
    """
    def fobj(preds: np.ndarray, dataset):
        y = dataset.get_label().astype(np.float64)
        z = np.asarray(preds, dtype=np.float64)
        grad = _focal_grad(z, y, gamma, alpha)
        hess = (_focal_grad(z + eps, y, gamma, alpha)
                - _focal_grad(z - eps, y, gamma, alpha)) / (2.0 * eps)
        hess = np.maximum(hess, 1e-6)

        w = dataset.get_weight()          # LightGBM will NOT do this for us
        if w is not None:
            w = np.asarray(w, dtype=np.float64)
            grad = grad * w
            hess = hess * w
        return grad, hess

    fobj.__name__ = f"focal_g{gamma}_a{alpha}"
    return fobj


def focal_loss_value(z: np.ndarray, y: np.ndarray, gamma: float = 2.0,
                     alpha: float = 0.25) -> float:
    """Mean focal loss — used only by the unit tests to check the gradient."""
    p = _sigmoid(z)
    pt = np.clip(y * p + (1.0 - y) * (1.0 - p), 1e-9, 1.0 - 1e-9)
    at = alpha * y + (1.0 - alpha) * (1.0 - y)
    return float(np.mean(-at * (1.0 - pt) ** gamma * np.log(pt)))
