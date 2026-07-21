"""Validate Airflow DAGs parse without errors."""

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
