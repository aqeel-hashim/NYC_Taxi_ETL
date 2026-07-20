# ADR-0001: KubernetesExecutor for Local Airflow

## Status

Accepted.

## Context

Assignment 1 requires a modern orchestrator (Dagster/Prefect/Airflow) to run a batch ETL pipeline locally. Airflow provides multiple executor options: SequentialExecutor, LocalExecutor, CeleryExecutor, DockerExecutor, and KubernetesExecutor.

The implementation plan targets a local kind cluster with Helm-deployed services (PostgreSQL via CloudNativePG, MinIO, monitoring stack). Running Airflow's task pods directly on the same cluster provides resource isolation, restart safety, and a single control plane.

## Decision

Use Apache Airflow with **KubernetesExecutor** on a local kind cluster.

Each Airflow task runs in an isolated pod with explicit resource requests/limits. The DAGs and ETL package are baked into an immutable Airflow image.

## Alternatives Considered

- **DockerExecutor**: Simpler but lacks pod-level isolation and resource limits. Tasks share the scheduler's compute.
- **LocalExecutor**: No isolation. Not suitable for heavy transform workloads that may OOM.
- **CeleryExecutor**: Adds Redis/RabbitMQ dependency. KubernetesExecutor is simpler on an existing cluster.
- **Dagster/Prefect**: Valid alternatives. Airflow chosen for its mature Helm chart, StatsD metrics, and broader ecosystem.

## Consequences

- Requires kind cluster, Kubernetes RBAC, and pod template configuration.
- Task images must be pre-built and loaded into kind.
- Adds cluster provisioning complexity to setup but enables unified monitoring/security.
- Production target (EKS) mirrors local topology.
