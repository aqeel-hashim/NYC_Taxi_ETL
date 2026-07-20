# ADR-0002: MinIO as Local Object Store

## Status

Accepted.

## Context

The pipeline handles raw Parquet downloads, transform checkpoints, reference snapshots, quarantine, Airflow remote task logs, Loki log chunks, and PostgreSQL backups. These artifacts need durable, versioned, checksum-addressed storage shared between Airflow tasks, CNPG backup, and Loki.

## Decision

Use **MinIO** (S3-compatible) as the local object store with host-persisted storage.

Raw source objects are checksum-addressed and write-once. Checkpoints are versioned and lifecycle-managed. Quarantine is partitioned. Logs and backups use dedicated buckets with retention policies.

## Alternatives Considered

- **Host filesystem mounts**: No versioning, no S3 API, no lifecycle, harder to isolate per-component access.
- **Local-path PVC only**: No cross-pod sharing without RWX, no versioning, no S3 API for backup tooling.
- **Direct S3 for local dev**: Requires AWS credentials and network; adds latency and cloud dependency.

## Consequences

- Adds MinIO operator/deployment to the cluster.
- Requires static hostPath PV to persist data across kind deletions.
- Bucket lifecycle policies must be configured and tested.
- Production migration to S3 is mechanical: swap endpoint/credentials.
- All components that need object storage (Airflow remote logging, CNPG backup, Loki) integrate through S3-compatible API.
