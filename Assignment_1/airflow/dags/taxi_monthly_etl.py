from __future__ import annotations

import os
from datetime import datetime, timedelta
from pathlib import Path

import requests
from alerting import notify_failure

from airflow.decorators import dag, task
from nyc_taxi_etl.pipeline import run_pipeline

DEFAULT_ARGS = {
    "owner": "taxi",
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(hours=2),
    "pool": "taxi_etl_pool",
}
SOURCE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{month}.parquet"


def _source_month(context: dict[str, object]) -> str:
    dag_run = context.get("dag_run")
    conf = getattr(dag_run, "conf", {}) or {}
    if "source_month" in conf:
        return str(conf["source_month"])
    if os.environ.get("NYC_TAXI_FIXTURE_MODE") == "true":
        return "2023-01"
    data_interval_start = context.get("data_interval_start")
    if isinstance(data_interval_start, datetime):
        previous_month = data_interval_start.replace(day=1) - timedelta(days=1)
        return previous_month.strftime("%Y-%m")
    return "2023-01"


@dag(
    dag_id="taxi_monthly_etl",
    default_args=DEFAULT_ARGS,
    schedule="0 6 5 * *",
    start_date=datetime(2023, 1, 1),
    catchup=False,
    max_active_runs=1,
    on_failure_callback=notify_failure,
    tags=["taxi", "etl"],
)
def taxi_monthly_etl() -> None:
    @task(task_id="check_source")
    def check_source(**context: object) -> str:
        month = _source_month(context)
        if Path(f"data/yellow_tripdata_{month}.parquet").is_file():
            return month
        url = SOURCE_URL.format(month=month)
        resp = requests.head(url, timeout=10)
        resp.raise_for_status()
        return month

    @task(task_id="publish_month")
    def publish_month(month: str) -> dict[str, int]:
        result = run_pipeline(
            month,
            database_url=os.environ["DATABASE_URL"],
            fixture=os.environ.get("NYC_TAXI_FIXTURE_MODE") == "true",
        )
        return {
            "source_rows": result.source_rows,
            "accepted_rows": result.accepted_rows,
            "rejected_rows": result.rejected_rows,
            "flagged_rows": result.flagged_rows,
        }

    @task(task_id="complete")
    def complete(counts: dict[str, int]) -> None:
        print(
            "pipeline_complete "
            f"source={counts['source_rows']} accepted={counts['accepted_rows']} "
            f"rejected={counts['rejected_rows']} flagged_rows={counts['flagged_rows']}"
        )

    month = check_source()
    counts = publish_month(month=month)  # type: ignore[arg-type]
    complete(counts)  # type: ignore[arg-type]


taxi_monthly_etl()
