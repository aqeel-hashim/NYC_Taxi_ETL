# Architecture

## Local Platform

namespacing allows for easier management, especially for cases where you want
to monitor a specfic part of the stack, or gracefully restart it.
kind cluster with five namespaces:

| Namespace | Contents |
|-----------|----------|
| `ingress` | Traefik, CoreDNS rewrites |
| `identity` | Dex, oauth2-proxy |
| `monitoring` | kube-prometheus-stack, Loki, Grafana Alloy |
| `data-platform` | Airflow KubernetesExecutor, CloudNativePG, PgBouncer, MinIO |
| `taxi-app` | Streamlit dashboard, webhook receiver, Mailpit |

### Data Flow

1. Airflow `BashOperator` downloads Yellow Taxi Parquet via `curl` from TLC CloudFront.
2. Source file is validated (schema fingerprint, row count) and stored in MinIO (checksum-addressed, write-once).
3. Reference files (zones, vendors, payments, rate codes) are resolved and SCD2 dimensions synced.
4. Polars transforms raw data in bounded batches: convert to integer cents/millimiles/seconds, validate, flag outliers.
    1. Integer conversion was a technical decision to avoid precision and performance issues with floating point
    1. Can expand later when we have time to support variable bit length integer support where applicable, not
    necessary now
5. Accepted rows, quality issues, and quarantine rejects are checkpointed to MinIO as Parquet.
6. Replacement fact and mart partitions are loaded via psycopg COPY into PostgreSQL.
7. Atomic partition swap publishes the month: detach old, attach new, increment warehouse version.
8. Streamlit dashboard reads from the analytics mart with versioned cache.

### Resource Profiles

- **Concurrent**: Full stack runs together. Minimum 8 GiB Docker memory, 4 CPUs.
- **Staged**: Scales Grafana/Streamlit down during ETL. One heavy task pod. Suitable for Small PC (4 CPU, 3.8 GiB).
- Auto-detected from Docker preflight; `--profile` override available.

### Security

- Default-deny Calico network policies per namespace.
- Per-service Kubernetes service accounts; no default tokens where unused.
- Generated Kubernetes Secrets from gitignored environment files.
- PostgreSQL roles: migrator/owner, loader, Airflow metadata, dashboard read-only, webhook writer, monitoring.
- Containers: non-root (where upstream permits), read-only root filesystem, seccomp, resource limits.
- mkcert-generated TLS for all `*.taxi.localhost` services.
- Dex admin/viewer groups map to least-privilege roles.

### Production (AWS)

See [ADR-0009](adr/0009-aws-eks-production.md). EKS, Aurora Global Database, S3, Cognito, Cloudflare, DR in `us-west-2`.
