from __future__ import annotations

from pathlib import Path

import yaml  # type: ignore[import-untyped]

ROOT = Path(__file__).parents[2]
INFRA = ROOT / "infra" / "local"


def test_phase9_values_are_bounded_and_secret_free() -> None:
    prometheus = (INFRA / "values" / "prometheus.yaml").read_text()
    loki = (INFRA / "values" / "loki.yaml").read_text()

    assert "retention: 14d" in prometheus
    assert "storage: 5Gi" in prometheus
    assert "retention_period: 336h" in loki
    assert "adminPassword:" not in prometheus
    assert "credentials_file:" in prometheus


def test_phase9_has_rules_and_two_loki_linked_dashboards() -> None:
    documents = list(yaml.safe_load_all((INFRA / "manifests" / "phase9-observability.yaml").read_text()))
    rule = next(document for document in documents if document and document["kind"] == "PrometheusRule")
    alerts = {item["alert"] for item in rule["spec"]["groups"][0]["rules"] if "alert" in item}
    dashboards = [
        document for document in documents if document and document["metadata"]["name"].startswith("grafana-dashboard")
    ]

    assert {"TaxiBatchFailure", "PrometheusTargetMissing", "CNPGBackupStale"} <= alerts
    assert len(dashboards) == 2
    assert all("logs" in next(iter(document["data"].values())) for document in dashboards)


def test_backup_and_restore_use_plugin_and_temporary_cluster() -> None:
    backup = (ROOT / "scripts" / "backup.sh").read_text()
    restore = (ROOT / "scripts" / "restore-drill.sh").read_text()

    assert "plugin-barman-cloud/releases/download/v${PLUGIN_VERSION}" in backup
    assert "method: plugin" in backup
    assert "restore-drill" in restore
    assert "fact_taxi_trips" in restore
    assert "kubectl delete namespace" in restore
