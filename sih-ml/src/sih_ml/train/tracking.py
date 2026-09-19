"""Thin MLflow wrapper — local SQLite backend, no tracking server required.

MLflow 3.x put the old `./mlruns` *file* store into maintenance mode and refuses
it by default, so we use the recommended local alternative: a SQLite tracking DB
(`mlruns/mlflow.db`) with artifacts written alongside it.

Every Stage 4 training run is one MLflow parent run with a nested child run per
CV fold. Params, per-round train/val curves (as step-indexed metrics), final
metrics, and artifacts (plots, configs, the model itself) are all logged, so
`mlflow ui --backend-store-uri sqlite:///mlruns/mlflow.db` gives a full
experiment history without re-reading any of our own JSON files.
"""
from __future__ import annotations

import contextlib
from pathlib import Path

import mlflow

from sih_ml.utils.common import REPO_ROOT, get_logger

log = get_logger("tracking")

EXPERIMENT_NAME = "sih-disruption"


def init_tracking(tracking_dir: str | Path | None = None) -> None:
    d = Path(tracking_dir or (REPO_ROOT / "mlruns"))
    d.mkdir(parents=True, exist_ok=True)
    mlflow.set_tracking_uri(f"sqlite:///{d / 'mlflow.db'}")
    mlflow.set_experiment(EXPERIMENT_NAME)
    log.info("MLflow tracking -> sqlite:///%s", d / "mlflow.db")


@contextlib.contextmanager
def run(name: str, params: dict | None = None, nested: bool = False, tags: dict | None = None):
    with mlflow.start_run(run_name=name, nested=nested, tags=tags) as r:
        if params:
            mlflow.log_params(_flatten(params))
        yield r


def log_curve(history: dict[str, dict[str, list[float]]], prefix: str = "") -> None:
    """history: {valid_name: {metric_name: [v_round0, v_round1, ...]}} from
    lgb.record_evaluation — logs every point as a step-indexed MLflow metric."""
    for valid_name, metrics in history.items():
        for metric_name, values in metrics.items():
            key = f"{prefix}{valid_name}_{metric_name}"
            for step, v in enumerate(values):
                mlflow.log_metric(key, float(v), step=step)


def log_metrics(d: dict, prefix: str = "") -> None:
    flat = _flatten(d, prefix)
    mlflow.log_metrics({k: v for k, v in flat.items() if isinstance(v, (int, float))})


def log_artifact(path: str | Path, artifact_path: str | None = None) -> None:
    mlflow.log_artifact(str(path), artifact_path=artifact_path)


def _flatten(d: dict, prefix: str = "") -> dict:
    out = {}
    for k, v in d.items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(_flatten(v, key + "."))
        elif isinstance(v, (list, tuple)):
            out[key] = str(v)[:250]
        else:
            out[key] = v
    return out
