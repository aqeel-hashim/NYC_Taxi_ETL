from __future__ import annotations

import os
import subprocess
from datetime import datetime
from pathlib import Path

import polars as pl

from airflow.decorators import dag, task
from nyc_taxi_etl.quality.kll import (
    DEFAULT_K,
    ThresholdVersion,
    build_sketch_from_iterable,
    compute_bounds,
    save_threshold_version,
)
from nyc_taxi_etl.transform.trips import transform

SOURCE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{month}.parquet"
CALIBRATION_BASELINE = ["2023-01", "2023-02"]
KLL_DIR = os.environ.get("KLL_THRESHOLD_DIR", "data/thresholds")


@dag(
    dag_id="taxi_quality_calibration",
    schedule=None,
    start_date=datetime(2023, 1, 1),
    catchup=False,
    tags=["taxi", "quality"],
)
def taxi_quality_calibration() -> None:
    @task(task_id="calibrate_from_baseline")
    def calibrate() -> str:
        sketches: dict[str, list[float]] = {
            "duration_seconds": [],
            "distance_millimiles": [],
        }
        version = ThresholdVersion(
            version_id="2023-baseline-v1",
            baseline_months=CALIBRATION_BASELINE,
            k_value=DEFAULT_K,
        )

        for month in CALIBRATION_BASELINE:
            path = Path(f"data/yellow_tripdata_{month}.parquet")
            if not path.exists():
                url = SOURCE_URL.format(month=month)
                subprocess.run(["curl", "-fL", url, "-o", str(path)], check=True)
            raw = pl.read_parquet(path)
            result = transform(raw, month)
            for s in result.accepted["duration_seconds"]:
                if s is not None and 0 < s < 86400:
                    sketches["duration_seconds"].append(float(s))
            for d in result.accepted["distance_millimiles"]:
                if d is not None and 0 < d < 1_000_000:
                    sketches["distance_millimiles"].append(float(d))

        for metric, values in sketches.items():
            if len(values) > 100:
                sketch = build_sketch_from_iterable(values, k=DEFAULT_K)
                version.bounds[metric] = compute_bounds(sketch, metric)

        version.is_active = True
        calibration_path = save_threshold_version(version, KLL_DIR)
        return str(calibration_path)

    @task(task_id="complete")
    def complete(path: str) -> None:
        print(f"calibration_complete path={path}")

    complete(calibrate())  # type: ignore[arg-type]


taxi_quality_calibration()
