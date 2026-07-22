# Local Lifecycle

## Evaluator Path

```bash
bash ./setup.sh --local-demo
bash ./setup.sh --local-demo --no-dashboard
bash ./teardown.sh --local
```

`--local-demo` is idempotent: it reuses valid downloads, the repo-local Python/tool cache, and the PostgreSQL volume. Monthly facts and quality records are replaced, not appended. Airflow metadata retains run history.

Runtime state is intentionally excluded from Git and release ZIPs:

| Path | Contents |
|---|---|
| `.tools/` | pinned uv, managed Python, package cache |
| `.venv/` | Python environment |
| `.env` | generated local secrets |
| `.local/airflow/` | local Airflow metadata/log state |
| `.local/logs/` | retained monthly Airflow command logs |
| `data/` | official Parquet and rejected-row quarantine |
| Docker volume `nyc-taxi-a1_pgdata` | PostgreSQL warehouse |

`teardown.sh --local` stops Compose while preserving the volume. `--purge-all --yes` removes all local state and volumes.

## Optional Extended Platform

The original staged lifecycle remains available for Kubernetes development:

```bash
./setup.sh --profile staged --tools core
./setup.sh --from etl --profile staged
./teardown.sh
```

It installs kind, Helm, CloudNativePG, MinIO, Airflow KubernetesExecutor, identity, and observability components. This path is resource-heavy and not the default evaluator workflow.
