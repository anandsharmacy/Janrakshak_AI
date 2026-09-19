"""Shared helpers: config loading, seeding, logging, hashing, path resolution."""
from __future__ import annotations

import hashlib
import json
import logging
import os
import random
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]  # sih-ml/


# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #
class Config(dict):
    """dict with attribute access and nested resolution."""

    def __getattr__(self, k: str) -> Any:
        try:
            v = self[k]
        except KeyError as e:
            raise AttributeError(k) from e
        return Config(v) if isinstance(v, dict) else v


def load_config(path: str | Path | None = None) -> Config:
    path = Path(path) if path else REPO_ROOT / "conf" / "config.yaml"
    with open(path) as f:
        raw = yaml.safe_load(f)
    return Config(raw)


def _deep_merge(base: dict, override: dict) -> dict:
    out = dict(base)
    for k, v in override.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config_with_base(path: str | Path, _seen: set | None = None) -> Config:
    """Load a config that may declare `base_config: <relative path>` — the base is
    loaded first, then this file's own keys are deep-merged on top (so a Stage 4
    config can inherit all of conf/model_baseline.yaml and only override what
    differs, e.g. model_version / paths.reports).

    RECURSIVE: base configs may themselves declare a base, so chains like
    hpo_config -> train_config -> model_baseline resolve fully. (Resolving only one
    level silently dropped every key defined two levels down.)"""
    path = Path(path).resolve()
    _seen = _seen or set()
    if path in _seen:
        raise ValueError(f"circular base_config chain at {path}")
    _seen.add(path)

    with open(path) as f:
        raw = yaml.safe_load(f)
    base_rel = raw.pop("base_config", None)
    if base_rel:
        base = load_config_with_base(REPO_ROOT / base_rel, _seen)
        raw = _deep_merge(dict(base), raw)
    return Config(raw)


def resolve(cfg: Config, rel: str) -> Path:
    """Resolve a config path (relative to repo root) to an absolute Path."""
    p = Path(rel)
    return p if p.is_absolute() else (REPO_ROOT / p).resolve()


# --------------------------------------------------------------------------- #
# Reproducibility
# --------------------------------------------------------------------------- #
def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)


def git_sha() -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(REPO_ROOT), "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL,
        ).decode().strip()
    except Exception:
        return "nogit"


# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    if not logger.handlers:
        h = logging.StreamHandler()
        h.setFormatter(logging.Formatter("%(asctime)s | %(levelname)-7s | %(name)s | %(message)s"))
        logger.addHandler(h)
        logger.setLevel(logging.INFO)
        # Child loggers ("stage7.ens") otherwise emit once via their own handler and
        # again via the parent's, double-printing every line.
        logger.propagate = False
    return logger


# --------------------------------------------------------------------------- #
# Hashing / manifests
# --------------------------------------------------------------------------- #
def sha256_file(path: str | Path, head_bytes: int | None = None) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        if head_bytes:
            h.update(f.read(head_bytes))
        else:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def hash_sources(paths: dict[str, Path]) -> dict[str, dict]:
    out = {}
    for name, p in paths.items():
        p = Path(p)
        if not p.exists():
            out[name] = {"path": str(p), "exists": False}
            continue
        st = p.stat()
        out[name] = {
            "path": str(p),
            "exists": True,
            "bytes": st.st_size,
            "mtime": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(),
            "sha256": sha256_file(p),
        }
    return out


def write_manifest(manifest_dir: str | Path, name: str, payload: dict) -> Path:
    manifest_dir = Path(manifest_dir)
    manifest_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "_generated_utc": datetime.now(timezone.utc).isoformat(),
        "_git_sha": git_sha(),
        **payload,
    }
    out = manifest_dir / f"{name}.json"
    with open(out, "w") as f:
        json.dump(payload, f, indent=2, default=str)
    return out


def check_sources_lock(manifest_dir: str | Path, current: dict[str, dict], logger) -> None:
    """Compare current source hashes against sources.lock.json; warn on drift.

    Rationale (see memory sih-parallel-worker): data2/ is edited concurrently by
    another agent + Jupyter kernels. We do not hard-fail, but every drift is logged
    loudly so a stale build is never silently documented.
    """
    lock_path = Path(manifest_dir) / "sources.lock.json"
    if not lock_path.exists():
        with open(lock_path, "w") as f:
            json.dump(current, f, indent=2, default=str)
        logger.info("wrote initial sources.lock.json (%d sources)", len(current))
        return
    with open(lock_path) as f:
        locked = json.load(f)
    drift = []
    for name, cur in current.items():
        old = locked.get(name)
        if old and old.get("sha256") != cur.get("sha256"):
            drift.append(name)
    if drift:
        logger.warning("SOURCE DRIFT since lock: %s — rebuild all downstream artifacts", drift)
    else:
        logger.info("all %d sources match sources.lock.json", len(current))
