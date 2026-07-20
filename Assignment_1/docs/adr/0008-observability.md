# ADR-0008: Observability with kube-prometheus-stack and Loki

## Status

Accepted.

## Context

The platform must capture Airflow task metrics, PostgreSQL performance, MinIO errors, pod health, and structured logs. The assignment requires pipeline logging (start/end times, row counts, error handling) and orchestration alerts.

Prometheus and Grafana are the assignment-required stack for Assignment 2. Consistency between assignments reduces cognitive load.

## Decision

Use **kube-prometheus-stack** (Prometheus operator, Grafana, Alertmanager, node exporter, kube-state-metrics) for metrics and alerting, and **Loki** (with Grafana Alloy) for log aggregation.

- Prometheus scrapes Airflow StatsD exporter, CNPG/PostgreSQL exporter, MinIO metrics, kube-state-metrics, node exporter, and Pushgateway.
- Loki ingests Airflow task logs (JSON structured), webhook receiver logs, and application logs.
- Two Grafana dashboards: `Platform Health` (cluster/services) and `Batch Pipeline` (ETL-specific).
- Alertmanager routes to Mailpit (SMTP) and webhook receiver.
- Pushgateway for bounded batch outcome metrics with group replacement to avoid stale series.
- Retention: Prometheus 14 days (5 GiB PVC), Loki 14 days (5 GiB MinIO bucket).

## Alternatives Considered

- **ELK stack**: Heavier than Loki for log aggregation. Loki integrates natively with Grafana.
- **CloudWatch only**: Not available locally. Production adds AMP/AMG.
- **No local monitoring**: Would require manual log inspection; defeats the assignment's observability requirements.

## Consequences

- Significant cluster resource consumption (Prometheus TSDB, Loki chunk storage, Grafana).
- Staged profile may need to scale Grafana down during ETL.
- Metric label cardinality must be controlled (no trip ID, checksum, or exception text as labels).
- Lifecycle policies and quota enforcement prevent unbounded disk growth.
