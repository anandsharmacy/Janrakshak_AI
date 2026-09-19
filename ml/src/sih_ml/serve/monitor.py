"""Monitoring: service metrics (Prometheus text format) + input-drift checks.

What is worth alerting on for THIS model, in order of how likely it is to hurt:

  1. rainfall feed freshness — the daily job refuses stale dates (validate.py); the
     gauge `sih_rain_feed_lag_days` makes the lag visible before a job fails.
  2. rainfall distribution drift — a feed swap (CHIRPS -> CHIRPS-prelim / IMERG /
     IMD) or a unit error changes the inputs the model's monotone rainfall response
     sits on. Compared per calendar month against the CHIRPS climatology, because
     rainfall is seasonal and a monsoon day always looks "drifted" against the year.
  3. alert volume — share of segments per tier per day; a step change is either a
     real event or an input fault, and both need a human.
  4. the usual: request rate, latency, error codes, model version.

No client library: the text exposition format is a few lines and this keeps the
serving image dependency-free.
"""
from __future__ import annotations

import threading
import time
from collections import defaultdict

import numpy as np
import pandas as pd

LATENCY_BUCKETS = (0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 10.0)
PSI_WARN = 0.25


class Metrics:
    def __init__(self):
        self._lock = threading.Lock()
        self.counters: dict[tuple, float] = defaultdict(float)
        self.gauges: dict[tuple, float] = {}
        self.hist: dict[tuple, list] = {}

    def inc(self, name: str, value: float = 1.0, **labels):
        with self._lock:
            self.counters[(name, tuple(sorted(labels.items())))] += value

    def set(self, name: str, value: float, **labels):
        with self._lock:
            self.gauges[(name, tuple(sorted(labels.items())))] = float(value)

    def observe(self, name: str, seconds: float, **labels):
        key = (name, tuple(sorted(labels.items())))
        with self._lock:
            h = self.hist.setdefault(key, [0] * (len(LATENCY_BUCKETS) + 1) + [0.0, 0])
            for i, b in enumerate(LATENCY_BUCKETS):
                if seconds <= b:
                    h[i] += 1
            h[len(LATENCY_BUCKETS)] += 1                 # +Inf
            h[-2] += seconds
            h[-1] += 1

    @staticmethod
    def _lbl(labels: tuple, extra: dict | None = None) -> str:
        items = list(labels) + list((extra or {}).items())
        return "{" + ",".join(f'{k}="{v}"' for k, v in items) + "}" if items else ""

    def render(self) -> str:
        out = []
        with self._lock:
            for (n, l), v in sorted(self.counters.items()):
                out.append(f"{n}{self._lbl(l)} {v:g}")
            for (n, l), v in sorted(self.gauges.items()):
                out.append(f"{n}{self._lbl(l)} {v:g}")
            for (n, l), h in sorted(self.hist.items()):
                for i, b in enumerate(LATENCY_BUCKETS):
                    out.append(f"{n}_bucket{self._lbl(l, {'le': b})} {h[i]}")
                out.append(f"{n}_bucket{self._lbl(l, {'le': '+Inf'})} {h[len(LATENCY_BUCKETS)]}")
                out.append(f"{n}_sum{self._lbl(l)} {h[-2]:.6f}")
                out.append(f"{n}_count{self._lbl(l)} {h[-1]}")
        return "\n".join(out) + "\n"


class Timer:
    def __init__(self):
        self.t0 = time.perf_counter()

    def __call__(self) -> float:
        return time.perf_counter() - self.t0


# --------------------------------------------------------------------------- #
# drift
# --------------------------------------------------------------------------- #
WINDOW_DAYS = 30


def _frames(r: pd.DataFrame, api_decay: float = 0.92, api_n: int = 30) -> dict:
    # API = sum_k r[t-k] * decay^k over the last api_n days (features/rainfall.py)
    return {"rain_7d_mm": r.rolling(7).sum(),
            "api_mm": sum(r.shift(k) * api_decay ** k for k in range(api_n))}


def rainfall_reference(rain: pd.DataFrame, end: str | None = None,
                       warn_quantile: float = 0.99) -> dict:
    """Per-month decile edges of cell-level 7-day rain and API, plus a warn threshold
    CALIBRATED on the record itself.

    Why a trailing window: on one day all ~119 cells sit under the same weather
    system, so a single day's cells are one sample, not 119, and a one-day PSI flags
    ordinary weather (measured: PSI 1.85 on an unremarkable 2025-08-15). A 30-day
    window of all cells is dominated by the feed's behaviour, which is what a unit
    error or a source swap changes. The threshold is the `warn_quantile` of the same
    statistic over every day of the record, per calendar month — so a warning means
    "rarer than 1 day in 100 historically", not a textbook 0.25.
    """
    r = rain if end is None else rain.loc[:end]
    frames = _frames(r)
    ref, warn = {}, {}
    for name, frame in frames.items():
        ref[name], warn[name] = {}, {}
        for m in range(1, 13):
            v = frame[frame.index.month == m].to_numpy().ravel()
            v = v[np.isfinite(v)]
            ref[name][str(m)] = np.quantile(v, np.linspace(0.1, 0.9, 9)).tolist()
        hist = []
        vals = frame.to_numpy()
        for i in range(WINDOW_DAYS + 30, len(frame)):
            m = frame.index[i].month
            hist.append((m, psi(vals[i - WINDOW_DAYS + 1:i + 1].ravel(), ref[name][str(m)])))
        h = pd.DataFrame(hist, columns=["m", "psi"])
        for m in range(1, 13):
            warn[name][str(m)] = float(h[h.m == m].psi.quantile(warn_quantile))
    return {"deciles": ref, "psi_warn": warn, "window_days": WINDOW_DAYS,
            "warn_quantile": warn_quantile, "record_end": str(r.index.max().date())}


def window_values(rain: pd.DataFrame, cutoff: pd.Timestamp) -> dict[str, np.ndarray]:
    """All cells' 7-day rain / API over the trailing window ending at `cutoff`."""
    r = rain.loc[:cutoff].iloc[-(WINDOW_DAYS + 40):]
    return {k: f.iloc[-WINDOW_DAYS:].to_numpy().ravel() for k, f in _frames(r).items()}


def psi(values: np.ndarray, decile_edges: list[float], eps: float = 1e-4) -> float:
    """Population stability index against a decile reference (10 equal-mass bins)."""
    v = np.asarray(values, float)
    v = v[np.isfinite(v)]
    if not len(v):
        return float("nan")
    b = np.bincount(np.searchsorted(decile_edges, v, side="right"), minlength=10) / len(v)
    e = np.full(10, 0.1)
    b = np.clip(b, eps, None)
    return float(np.sum((b - e) * np.log(b / e)))


def drift_report(rain: pd.DataFrame, cutoff: pd.Timestamp, reference: dict) -> dict:
    """Trailing-window PSI of the feed vs the same month's climatology, judged against
    the historically calibrated threshold (see rainfall_reference)."""
    month = str(pd.Timestamp(cutoff).month)
    out = {}
    for name, v in window_values(rain, cutoff).items():
        if name in reference["deciles"]:
            p = psi(v, reference["deciles"][name][month])
            thr = reference.get("psi_warn", {}).get(name, {}).get(month, PSI_WARN)
            out[name] = {"psi_30d_vs_month_climatology": p, "warn_threshold": thr,
                         "warn": bool(p > thr)}
    return out
