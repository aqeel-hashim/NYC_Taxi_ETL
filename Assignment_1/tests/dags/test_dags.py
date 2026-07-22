"""Validate Airflow DAGs parse without errors."""

import runpy
from collections.abc import Callable
from datetime import UTC, datetime
from types import SimpleNamespace
from typing import cast

import pytest

from airflow.models import DagBag


def test_dagbag_import() -> None:
    dagbag = DagBag(dag_folder="airflow/dags/", include_examples=False)
    assert dagbag.dags is not None
    assert len(dagbag.dags) == 3
    for dag_id in ("taxi_monthly_etl", "taxi_quality_calibration", "taxi_failure_drill"):
        assert dag_id in dagbag.dags, f"Missing DAG: {dag_id}"
        dag = dagbag.dags[dag_id]
        assert dag is not None
        assert len(dag.tasks) > 0
    assert len(dagbag.import_errors) == 0, f"Import errors: {dagbag.import_errors}"


def test_scheduled_run_selects_previous_calendar_month(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.syspath_prepend("airflow/dags")
    source_month = cast(
        Callable[[dict[str, object]], str],
        runpy.run_path("airflow/dags/taxi_monthly_etl.py")["_source_month"],
    )
    context: dict[str, object] = {
        "dag_run": SimpleNamespace(conf={}),
        "data_interval_end": datetime(2023, 3, 5, 6, tzinfo=UTC),
    }
    assert source_month(context) == "2023-02"
    context["dag_run"] = SimpleNamespace(conf={"source_month": "2023-01"})
    assert source_month(context) == "2023-01"
