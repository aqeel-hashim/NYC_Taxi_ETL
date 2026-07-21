from __future__ import annotations

from datetime import datetime

from airflow.decorators import dag, task


@dag(
    dag_id="taxi_quality_calibration",
    schedule=None,
    start_date=datetime(2023, 1, 1),
    catchup=False,
    tags=["taxi", "quality"],
)
def taxi_quality_calibration() -> None:
    @task(retries=0)
    def calibration_not_implemented() -> None:
        raise NotImplementedError("Quality calibration needs persisted baseline data before activation")

    calibration_not_implemented()


taxi_quality_calibration()
