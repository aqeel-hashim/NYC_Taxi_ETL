"""KLL sketch calibration: build, merge, serialize, threshold versioning.

Uses Apache DataSketches KLL with k=4096.
Streams numeric batches, computes quantile bounds for outlier detection.

Uses the KLL strategy to find bounds within dataset to identify reasonable
outliers.
"""

from __future__ import annotations

import json
import os
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime

from datasketches import kll_floats_sketch

# Higher precision than the library default for multi-million-row months.
DEFAULT_K = 4096
BOUND_QUANTILE_LOW = 0.001
BOUND_QUANTILE_HIGH = 0.999


@dataclass
class ThresholdBounds:
    metric: str
    k_value: int
    low_quantile: float
    high_quantile: float
    low_bound: float
    high_bound: float

    def is_outlier(self, value: float) -> bool:
        return value < self.low_bound or value > self.high_bound


@dataclass
class ThresholdVersion:
    version_id: str
    baseline_months: list[str]
    k_value: int
    bounds: dict[str, ThresholdBounds] = field(default_factory=dict)
    created_at: str = ""
    is_active: bool = False

    def __post_init__(self) -> None:
        if not self.created_at:
            self.created_at = datetime.now(UTC).isoformat()

    def get_bounds(self, metric: str) -> ThresholdBounds:
        if metric not in self.bounds:
            raise KeyError(f"No bounds for metric: {metric}")
        return self.bounds[metric]


def build_sketch(values: list[float], k: int = DEFAULT_K) -> kll_floats_sketch:
    sketch = kll_floats_sketch(k)
    for v in values:
        sketch.update(v)
    return sketch


def build_sketch_from_iterable(values: Iterable[float], k: int = DEFAULT_K) -> kll_floats_sketch:
    sketch = kll_floats_sketch(k)
    for v in values:
        sketch.update(v)
    return sketch


def merge_sketches(*sketches: kll_floats_sketch, k: int = DEFAULT_K) -> kll_floats_sketch:
    merged = kll_floats_sketch(k)
    for s in sketches:
        merged.merge(s)
    return merged


def compute_bounds(
    sketch: kll_floats_sketch,
    metric: str,
    low_q: float = BOUND_QUANTILE_LOW,
    high_q: float = BOUND_QUANTILE_HIGH,
) -> ThresholdBounds:
    return ThresholdBounds(
        metric=metric,
        k_value=sketch.k,
        low_quantile=low_q,
        high_quantile=high_q,
        low_bound=sketch.get_quantile(low_q),
        high_bound=sketch.get_quantile(high_q),
    )


def serialize_sketch(sketch: kll_floats_sketch) -> bytes:
    return sketch.serialize()  # type: ignore[no-any-return]


def deserialize_sketch(data: bytes) -> kll_floats_sketch:
    return kll_floats_sketch.deserialize(data)


def save_threshold_version(version: ThresholdVersion, directory: str) -> str:
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, f"{version.version_id}.json")
    payload: dict[str, object] = {
        "version_id": version.version_id,
        "baseline_months": version.baseline_months,
        "k_value": version.k_value,
        "created_at": version.created_at,
        "is_active": version.is_active,
        "bounds": {
            m: {
                "metric": b.metric,
                "k_value": b.k_value,
                "low_quantile": b.low_quantile,
                "high_quantile": b.high_quantile,
                "low_bound": b.low_bound,
                "high_bound": b.high_bound,
            }
            for m, b in version.bounds.items()
        },
    }
    with open(path, "w") as f:
        json.dump(payload, f, indent=2)
    return path


def load_threshold_version(version_id: str, directory: str) -> ThresholdVersion:
    path = os.path.join(directory, f"{version_id}.json")
    with open(path) as f:
        data = json.load(f)
    bounds = {
        m: ThresholdBounds(
            metric=b["metric"],
            k_value=b["k_value"],
            low_quantile=b["low_quantile"],
            high_quantile=b["high_quantile"],
            low_bound=b["low_bound"],
            high_bound=b["high_bound"],
        )
        for m, b in data["bounds"].items()
    }
    return ThresholdVersion(
        version_id=data["version_id"],
        baseline_months=data["baseline_months"],
        k_value=data["k_value"],
        bounds=bounds,
        created_at=data["created_at"],
        is_active=data["is_active"],
    )
