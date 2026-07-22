# Assignment 1 Demo Runbook

## Fresh Machine

```bash
cd Assignment_1
bash ./setup.sh --local-demo
```

Wait for:

```text
Warehouse verified: {'202301': 2998637, '202302': 2850602}; total=5,849,239
Dashboard: http://localhost:8501
```

Open <http://localhost:8501>.

## Inspect Running Services

In a second terminal:

```bash
docker compose --project-name nyc-taxi-a1 --env-file .env \
  -f infra/local/compose.postgres.yaml ps postgres

set -a; source .env; set +a
.venv/bin/python - <<'PY'
import os
import psycopg

url = os.environ['DATABASE_URL'].replace('postgresql+psycopg://', 'postgresql://')
with psycopg.connect(url) as conn:
    print(conn.execute('''
        SELECT left(pickup_date_key::text, 6), count(*)
        FROM warehouse.fact_taxi_trips GROUP BY 1 ORDER BY 1
    ''').fetchall())
PY
```

Expected: `[('202301', 2998637), ('202302', 2850602)]`.

## Required SQL

```bash
set -a; source .env; set +a
.venv/bin/python - <<'PY'
import os
from pathlib import Path
import psycopg

url = os.environ['DATABASE_URL'].replace('postgresql+psycopg://', 'postgresql://')
with psycopg.connect(url) as conn:
    for path in sorted(Path('sql/queries').glob('*.sql')):
        print(f'\n=== {path.name} ===')
        for row in conn.execute(path.read_text()).fetchall():
            print(row)
PY
```

## Airflow Evidence

Successful monthly task logs:

```bash
grep -E 'pipeline_(started|completed)|Task exited with return code 0' .local/logs/airflow-2023-*.log
```

Controlled failure proof (expected nonzero command):

```bash
set -a; source .env; set +a
export AIRFLOW_HOME="$PWD/.local/airflow"
export AIRFLOW__CORE__DAGS_FOLDER="$PWD/airflow/dags"
export AIRFLOW__CORE__LOAD_EXAMPLES=false
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="sqlite:///$AIRFLOW_HOME/airflow.db"
export PYTHONPATH="$PWD"
.venv/bin/airflow dags test taxi_failure_drill 2023-03-06T06:00:00+00:00
```

Airflow must mark `controlled_fail` and the DAG run failed. The failure callback logs channel status without leaking exception text or secrets. External webhook/SMTP delivery is optional extended-platform functionality.

## Validation

```bash
VERIFY_IMAGES=false ./scripts/verify.sh
```

## Stop

```bash
bash ./teardown.sh --local
```

To delete all local tools, data, secrets, and Docker volumes:

```bash
bash ./teardown.sh --purge-all --yes
```

## Troubleshooting

| Symptom | Action |
|---|---|
| Docker daemon unreachable | Start Docker using the evaluator's distro/Desktop instructions; setup does not invoke service managers |
| Docker permission denied | Configure Docker group or rootless Docker; do not run project files as root |
| Port 5432 occupied | Stop the other PostgreSQL/container, then rerun |
| Port 8501 occupied | Stop the other dashboard process |
| Corporate TLS/proxy failure | Configure Docker, `curl`, and CA trust for the organization before rerunning |
| Interrupted source download | Rerun; `.part` downloads are discarded and Parquet headers/footers are revalidated |
| Less than 4 GiB RAM | Close other workloads; the setup processes one month at a time |
| Alpine/musl | Automatic bootstrap is unsupported; use a glibc Linux VM/container or WSL2 |
