"""The deployable model bundle — everything inference needs, nothing it doesn't.

    deploy/bundles/<version>/
        model.txt          LightGBM text model (portable, version-pinned by manifest)
        calibration.json   per-slope isotonic calibrators as (x, y) lookup tables
        schema.json        ordered features, categorical level maps, feature groups
        policy.json        operating threshold, steep-terrain rule, output caveats
        reference.json     drift references (per-month rainfall deciles by cell)
        manifest.json      version, lineage, sha256 of every file above

Why not ship models/final_v3/ as-is:
  * its calibrators are scikit-learn pickles — a pickle executes code on load and is
    tied to the exact sklearn version. An isotonic regression is a monotone
    piecewise-linear lookup; storing its knots as JSON reproduces it exactly (tested)
    and removes sklearn from the serving image;
  * serving must encode categoricals exactly as training did. LightGBM stores the
    training category levels in the model; schema.json makes them explicit and the
    loader checks the two agree;
  * `Bundle.load` verifies every file against the manifest. A bundle that has been
    edited, truncated or mixed with another version refuses to load.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd

BUNDLE_FILES = ("model.txt", "calibration.json", "schema.json", "policy.json", "reference.json")


class BundleError(RuntimeError):
    pass


def _sha(p: Path) -> str:
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


# --------------------------------------------------------------------------- #
@dataclass
class IsotonicTable:
    """Exact replacement for the fitted sklearn IsotonicRegression used by
    `models.calibration.Calibrator` (out_of_bounds='clip', inputs and outputs
    clipped to [1e-6, 1 - 1e-6], no prior shift)."""
    x: np.ndarray
    y: np.ndarray

    def __call__(self, p: np.ndarray) -> np.ndarray:
        p = np.clip(np.asarray(p, float), 1e-6, 1 - 1e-6)
        return np.clip(np.interp(p, self.x, self.y), 1e-6, 1 - 1e-6)

    def to_json(self) -> dict:
        return {"x": self.x.tolist(), "y": self.y.tolist()}

    @classmethod
    def from_json(cls, d: dict) -> "IsotonicTable":
        return cls(np.asarray(d["x"], float), np.asarray(d["y"], float))


def slope_stratum(slope: np.ndarray, bins: list[float]) -> np.ndarray:
    """Identical to optimize.calibrate.slope_stratum (tested)."""
    s = np.nan_to_num(np.asarray(slope, float), nan=0.0)
    return np.clip(np.digitize(s, bins[1:-1]), 0, len(bins) - 2)


class Calibration:
    def __init__(self, bins: list[float], pooled: IsotonicTable, strata: dict[int, IsotonicTable]):
        self.bins, self.pooled, self.strata = list(bins), pooled, strata

    def __call__(self, raw: np.ndarray, slope: np.ndarray) -> np.ndarray:
        s = slope_stratum(slope, self.bins)
        out = self.pooled(raw)
        for k, table in self.strata.items():
            m = s == k
            if m.any():
                out[m] = table(raw[m])
        return out


# --------------------------------------------------------------------------- #
class Bundle:
    def __init__(self, path: Path, booster: lgb.Booster, calibration: Calibration,
                 schema: dict, policy: dict, reference: dict, manifest: dict):
        self.path, self.booster, self.calibration = Path(path), booster, calibration
        self.schema, self.policy, self.reference, self.manifest = schema, policy, reference, manifest

    @property
    def version(self) -> str:
        return self.manifest["version"]

    @property
    def features(self) -> list[str]:
        return self.schema["features"]

    @classmethod
    def load(cls, path: str | Path, verify: bool = True) -> "Bundle":
        path = Path(path)
        mf = path / "manifest.json"
        if not mf.exists():
            raise BundleError(f"no manifest in {path}")
        manifest = json.loads(mf.read_text())
        if manifest.get("benchmark_only") and os.environ.get("SIH_ALLOW_BENCHMARK_BUNDLE") != "1":
            raise BundleError(f"{manifest['version']} is benchmark-only (calibrators were fitted "
                              "on a different model); refusing to serve it")
        if verify:
            for name in BUNDLE_FILES:
                want = manifest["files"].get(name)
                if want is None or not (path / name).exists() or _sha(path / name) != want:
                    raise BundleError(f"{name}: missing or sha256 mismatch — refusing to load")
        booster = lgb.Booster(model_file=str(path / "model.txt"))
        schema = json.loads((path / "schema.json").read_text())
        cal = json.loads((path / "calibration.json").read_text())
        calibration = Calibration(cal["bins"], IsotonicTable.from_json(cal["pooled"]),
                                  {int(k): IsotonicTable.from_json(v)
                                   for k, v in cal["strata"].items()})
        if booster.feature_name() != schema["features"]:
            raise BundleError("model feature order differs from schema")
        pc = getattr(booster, "pandas_categorical", None) or []
        if [list(x) for x in pc] != [schema["category_levels"][c] for c in schema["categorical"]]:
            raise BundleError("model category levels differ from schema")
        return cls(path, booster, calibration, schema,
                   json.loads((path / "policy.json").read_text()),
                   json.loads((path / "reference.json").read_text()), manifest)


# --------------------------------------------------------------------------- #
def build_bundle(model_dir: Path, out_dir: Path, *, policy: dict, reference: dict,
                 feature_groups: dict, calibration_bins: list[float],
                 num_iteration: int | None = None, extra_manifest: dict | None = None) -> Path:
    """Export models/<version>/ into a self-verifying bundle."""
    from sih_ml.models.calibration import Calibrator     # build time only

    model_dir, out_dir = Path(model_dir), Path(out_dir)
    card = json.loads((model_dir / "model_card.json").read_text())
    meta = json.loads((model_dir / "model.meta.json").read_text())
    if meta.get("raw_score"):
        raise BundleError("custom-objective (raw score) models are not supported by this bundle")
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    booster = lgb.Booster(model_file=str(model_dir / "model.txt"))
    k = num_iteration or booster.current_iteration()
    booster.save_model(str(out_dir / "model.txt"), num_iteration=k)

    def table(pkl: Path) -> IsotonicTable:
        c = Calibrator.load(pkl)
        if c.method != "isotonic" or c.target_prior_ is not None:
            raise BundleError(f"{pkl.name}: only prior-free isotonic calibrators are exported")
        return IsotonicTable(np.asarray(c.model_.X_thresholds_, float),
                             np.asarray(c.model_.y_thresholds_, float))

    strata = {int(p.stem.rsplit("_", 1)[1]): table(p).to_json()
              for p in sorted(model_dir.glob("calibrator_slope_*.pkl"))}
    (out_dir / "calibration.json").write_text(json.dumps({
        "method": "per-slope isotonic, fitted on dev out-of-fold scores",
        "bins": list(calibration_bins),
        "pooled": table(model_dir / "calibrator_pooled.pkl").to_json(),
        "strata": strata}))

    pc = booster.pandas_categorical or []
    schema = {"features": booster.feature_name(), "categorical": meta["categorical"],
              "category_levels": {c: list(levels) for c, levels in zip(meta["categorical"], pc)},
              "monotone_increasing": meta.get("monotone_increasing", []),
              "missing_category_token": "__missing__", **feature_groups}
    (out_dir / "schema.json").write_text(json.dumps(schema, indent=1))
    (out_dir / "policy.json").write_text(json.dumps(policy, indent=1))
    (out_dir / "reference.json").write_text(json.dumps(reference))

    truncated = k != booster.current_iteration()
    manifest = {"version": card["version"] + ("" if not truncated else f"-t{k}"),
                # A truncated model scores differently, so the full model's calibrators do
                # not fit it. Such a bundle is for latency benchmarking only until its
                # calibrators are refitted on its own out-of-fold scores.
                "benchmark_only": truncated,
                "source_model": str(model_dir), "source_config_sha256_16": card["config_sha256_16"],
                "lineage": card.get("lineage", []), "status": card.get("status"),
                "n_trees": int(k), "lightgbm_version": lgb.__version__,
                "created_utc": pd.Timestamp.now(tz="UTC").isoformat(),
                "files": {n: _sha(out_dir / n) for n in BUNDLE_FILES},
                **(extra_manifest or {})}
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1))
    return out_dir
