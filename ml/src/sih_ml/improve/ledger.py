"""Experiment ledger + champion registry.

Every experiment the loop runs — accepted or not — becomes one line in an
append-only JSONL file carrying enough to reproduce and audit it:

  * the hypothesis, the error pattern it targets and the layer it changes,
  * the exact change (one variable) and the champion it was measured against,
  * per-(fold, seed) AP for both sides, so any summary can be re-derived,
  * the decision, and the reason for it in words,
  * a fingerprint: hash of every source file, hash of the data artifacts, library
    versions and platform. The repo has no git, so `git_sha` alone would say "nogit";
    the source hash is what actually pins the code.

The registry (`models/registry.json`) is the single answer to "what is the best
model and why": the current champion, its lineage of accepted changes, and every
superseded version with its status. Nothing is ever deleted from either file.
"""
from __future__ import annotations

import hashlib
import json
import platform
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.utils.common import REPO_ROOT, sha256_file


def _js(x):
    if isinstance(x, (np.integer,)):
        return int(x)
    if isinstance(x, (np.floating,)):
        return None if not np.isfinite(x) else float(x)
    if isinstance(x, (np.bool_,)):
        return bool(x)
    if isinstance(x, np.ndarray):
        return x.tolist()
    if isinstance(x, (pd.Timestamp,)):
        return x.isoformat()
    return str(x)


def dumps(obj) -> str:
    return json.dumps(obj, default=_js, sort_keys=True)


def code_hash(root: Path = REPO_ROOT / "src") -> str:
    h = hashlib.sha256()
    for p in sorted(root.rglob("*.py")):
        h.update(str(p.relative_to(root)).encode())
        h.update(p.read_bytes())
    return h.hexdigest()[:16]


def data_hash(paths: list[Path]) -> str:
    h = hashlib.sha256()
    for p in paths:
        h.update(p.name.encode())
        h.update(sha256_file(p).encode())
    return h.hexdigest()[:16]


def environment() -> dict:
    import lightgbm
    import sklearn
    return {"python": sys.version.split()[0], "lightgbm": lightgbm.__version__,
            "numpy": np.__version__, "pandas": pd.__version__,
            "sklearn": sklearn.__version__, "platform": platform.platform(),
            "machine": platform.machine()}


def fingerprint(data_paths: list[Path]) -> dict:
    return {"code_sha16": code_hash(), "data_sha16": data_hash(data_paths),
            "env": environment()}


def spec_hash(spec: dict) -> str:
    return hashlib.sha256(dumps(spec).encode()).hexdigest()[:16]


# --------------------------------------------------------------------------- #
class Ledger:
    """Append-only JSONL. `append` is the only writer; there is no update/delete."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def append(self, entry: dict) -> dict:
        entry = {"utc": pd.Timestamp.now(tz="UTC").isoformat(), **entry}
        with self.path.open("a") as f:
            f.write(dumps(entry) + "\n")
        return entry

    def read(self) -> list[dict]:
        if not self.path.exists():
            return []
        return [json.loads(line) for line in self.path.read_text().splitlines() if line.strip()]

    def campaign(self, campaign_id: str) -> list[dict]:
        return [e for e in self.read() if e.get("campaign_id") == campaign_id]

    def last_campaign_id(self) -> str | None:
        ids = [e["campaign_id"] for e in self.read() if "campaign_id" in e]
        return ids[-1] if ids else None


# --------------------------------------------------------------------------- #
class Registry:
    """models/registry.json — the current champion and every version before it."""

    def __init__(self, path: Path):
        self.path = Path(path)

    def load(self) -> dict:
        if self.path.exists():
            return json.loads(self.path.read_text())
        return {"champion": None, "versions": []}

    def save(self, reg: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(reg, indent=2, default=_js))

    def ensure_version(self, reg: dict, version: dict) -> dict:
        """Add a version record if absent (versions are never rewritten once written,
        except for their `status`, which moves forward when superseded)."""
        if not any(v["version"] == version["version"] for v in reg["versions"]):
            reg["versions"].append(version)
        return reg

    def promote(self, reg: dict, version: dict, reason: str) -> dict:
        prev = reg.get("champion")
        for v in reg["versions"]:
            if prev and v["version"] == prev and v["version"] != version["version"]:
                v["status"] = f"superseded by {version['version']}"
        reg = self.ensure_version(reg, version)
        reg["champion"] = version["version"]
        reg["champion_reason"] = reason
        return reg
