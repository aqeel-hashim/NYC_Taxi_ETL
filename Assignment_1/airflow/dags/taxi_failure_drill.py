from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path

from airflow.decorators import dag, task
from airflow.exceptions import AirflowFailException


def write_failure_evidence(context: dict[str, object]) -> None:
    evidence_path = os.environ.get("ALERT_EVIDENCE_PATH")
    if not evidence_path:
        return
    task_instance = context.get("task_instance")
    payload = {
        "dag_id": getattr(task_instance, "dag_id", None),
        "run_id": context.get("run_id"),
        "task_id": getattr(task_instance, "task_id", None),
    }
    path = Path(evidence_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, sort_keys=True))


@dag(
    dag_id="taxi_failure_drill",
    schedule=None,
    start_date=datetime(2023, 1, 1),
    catchup=False,
    tags=["taxi", "test"],
    on_failure_callback=write_failure_evidence,
)
def taxi_failure_drill() -> None:
    @task(on_failure_callback=write_failure_evidence, retries=0)
    def controlled_fail() -> None:
        raise AirflowFailException("Controlled failure drill")

    controlled_fail()


taxi_failure_drill()
