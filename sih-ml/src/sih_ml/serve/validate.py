"""Input validation. Every rule here exists because of a specific way this model has
already been fed bad data, or would silently return a confident wrong answer.

The most important one is `check_date_scorable`. Stage 10 found 4,913 training rows
whose rainfall window ran past the end of the CHIRPS record; the builder silently
substituted the last available days, producing monsoon dates with "no rain". A
service that did the same would report low risk on exactly the days its rainfall
feed failed to update. Here a date whose window is incomplete is REFUSED.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

MAX_DAILY_MM = 1000.0          # far above any CHIRPS day in the corridor; a unit/feed error
MAX_ROWS_PER_REQUEST = 5000


class InputError(ValueError):
    def __init__(self, code: str, detail: str, status: int = 422):
        super().__init__(f"{code}: {detail}")
        self.code, self.detail, self.status = code, detail, status


def parse_date(s) -> pd.Timestamp:
    try:
        d = pd.Timestamp(str(s)).normalize()
    except (ValueError, TypeError):
        raise InputError("bad_date", f"expected YYYY-MM-DD, got {s!r}", 400)
    if pd.isna(d):
        raise InputError("bad_date", f"expected YYYY-MM-DD, got {s!r}", 400)
    return d


def check_date_scorable(date: pd.Timestamp, rain_start: pd.Timestamp, rain_end: pd.Timestamp,
                        horizon_days: int, history_days: int) -> None:
    cutoff = date - pd.Timedelta(days=horizon_days)
    if cutoff > rain_end:
        raise InputError("rainfall_not_available",
                         f"scoring {date.date()} needs rainfall through {cutoff.date()}; the "
                         f"feed ends {rain_end.date()}. Refusing rather than scoring on a "
                         f"truncated window.", 422)
    if cutoff - pd.Timedelta(days=history_days - 1) < rain_start:
        raise InputError("rainfall_history_too_short",
                         f"{date.date()} needs {history_days} days of history before "
                         f"{cutoff.date()}; the feed starts {rain_start.date()}", 422)


def check_rain_history(values, history_days: int) -> np.ndarray:
    try:
        v = np.asarray(values, float)
    except (TypeError, ValueError):
        raise InputError("bad_rainfall", "rain_mm must be a list of numbers", 400)
    if v.ndim != 1 or len(v) != history_days:
        raise InputError("bad_rainfall", f"rain_mm needs exactly {history_days} daily values, "
                         f"oldest first, ending the day before `date`; got {v.size}", 400)
    if not np.isfinite(v).all():
        raise InputError("bad_rainfall", "rain_mm contains NaN/inf — missing days must be "
                         "filled by the caller, not guessed by the model", 422)
    if (v < 0).any() or (v > MAX_DAILY_MM).any():
        raise InputError("bad_rainfall", f"daily rainfall must be within [0, {MAX_DAILY_MM:g}] "
                         "mm (a larger value is a unit or feed error)", 422)
    return v


def check_segment_ids(ids) -> list[str]:
    if ids is None or (isinstance(ids, (list, tuple)) and not ids):
        raise InputError("no_segments", "at least one segment_id is required", 400)
    if isinstance(ids, str):
        ids = [x for x in ids.split(",") if x]
    ids = list(dict.fromkeys(str(x) for x in ids))            # dedupe, keep order
    if len(ids) > MAX_ROWS_PER_REQUEST:
        raise InputError("too_many_segments", f"max {MAX_ROWS_PER_REQUEST} per request; "
                         "use the daily batch output for bulk reads", 413)
    return ids


def check_output(prob: np.ndarray, raw: np.ndarray) -> None:
    """A model bug must surface as a 500, not as a plausible-looking number."""
    if not (np.isfinite(prob).all() and np.isfinite(raw).all()):
        raise InputError("non_finite_output", "model produced a non-finite score", 500)
    if (prob < 0).any() or (prob > 1).any():
        raise InputError("bad_output", "calibrated probability outside [0, 1]", 500)
