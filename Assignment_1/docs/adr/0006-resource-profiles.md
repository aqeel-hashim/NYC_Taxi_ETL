# ADR-0006: Staged and Concurrent Resource Profiles

## Status

Accepted.

## Context

The implementation targets two machine profiles:
- **Big PC**: 16 CPU cores, 16 GiB host RAM, Docker in WSL2 (expected concurrent).
- **Small PC**: 4 CPU cores, 3.8 GiB RAM, no swap (must use staged).

Running the full stack (kind, CNPG, MinIO, Airflow, Prometheus, Grafana, Loki, Streamlit, Dex, Traefik, Mailpit) simultaneously may exceed Small PC memory or cause OOM. Big PC may also have constrained Docker-visible resources despite nominal host capacity.

## Decision

Implement **two resource profiles**: concurrent and staged.

- **Concurrent**: Full stack runs together. Requires at least 8 GiB Docker-visible memory and 4 CPUs.
- **Staged**: Keeps essential services (CNPG, MinIO, Airflow control plane, Prometheus exporters, Alertmanager, Mailpit, Dex, Traefik, Loki agents) during ETL. Scales Grafana and Streamlit down. One heavy ETL task pod at a time. Starts presentation services after ETL completes.
- **Auto-detection**: Docker preflight measurements decide profile. Explicit `--profile` flag overrides.
- **Stage-by-stage**: When even staged profile cannot retain 20% memory headroom, use documented stage-by-stage replay with explicit evidence.

## Alternatives Considered

- **One-size-fits-all**: Would fail on Small PC. Two profiles add complexity but enable both machines.
- **Separate Compose and kind deployments**: Adds maintenance burden, two different environments to debug.

## Consequences

- `setup.sh` must implement preflight, profile auto-selection, and service scaling.
- Staged profile must still capture metrics, logs, email, webhook, and alerts during ETL.
- Full-data acceptance runs on both profiles with separate benchmark evidence.
- Profile claims are always overridden by live Docker measurements.
