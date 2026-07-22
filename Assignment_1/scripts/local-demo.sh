#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${ROOT_DIR}/.tools/bin:${PATH}"
export UV_CACHE_DIR="${ROOT_DIR}/.tools/cache/uv"
export UV_PYTHON_INSTALL_DIR="${ROOT_DIR}/.tools/python"
source "${ROOT_DIR}/scripts/lib/logging.sh"

NO_DASHBOARD=false
case "${1:-}" in
  "") ;;
  --no-dashboard) NO_DASHBOARD=true; shift ;;
  -h|--help) printf 'Usage: ./scripts/local-demo.sh [--no-dashboard] [--help]\n'; exit 0 ;;
  *) printf 'Usage: ./scripts/local-demo.sh [--no-dashboard] [--help]\n' >&2; exit 2 ;;
esac
[[ $# -eq 0 ]] || { printf 'Usage: ./scripts/local-demo.sh [--no-dashboard] [--help]\n' >&2; exit 2; }

missing=()
for command_name in curl openssl docker tar gzip sha256sum awk grep find install df date dd tail ldd tee; do
  command -v "${command_name}" >/dev/null 2>&1 || missing+=("${command_name}")
done
if ((${#missing[@]})); then
  log_error "Missing host commands: ${missing[*]}"
  log_error "Install them with your distribution package manager; setup never invokes sudo."
  exit 1
fi
[[ "$(uname -s)" == Linux ]] || { log_error "Supported hosts: glibc Linux and WSL2"; exit 1; }
case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) log_error "Unsupported architecture: $(uname -m)"; exit 1 ;; esac
ldd --version 2>&1 | grep -Eiq 'glibc|GNU libc' || { log_error "Automatic bootstrap requires glibc Linux; Alpine/musl is unsupported"; exit 1; }
docker info >/dev/null 2>&1 || { log_error "Docker daemon is unreachable; start Docker and grant this user access"; exit 1; }
docker compose version >/dev/null 2>&1 || { log_error "Docker Compose v2 plugin is required"; exit 1; }
disk_kib="$(df -Pk "${ROOT_DIR}" | awk 'NR == 2 {print $4}')"
((disk_kib >= 5242880)) || { log_error "At least 5 GiB free disk is required"; exit 1; }
memory_kib="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
((memory_kib >= 4194304)) || log_warn "Less than 4 GiB RAM: process months sequentially and close other applications"

"${ROOT_DIR}/scripts/bootstrap-tools.sh" --profile uv
hash -r
uv python install 3.12
uv sync --frozen --no-dev --group airflow --group dashboard

if [[ ! -s "${ROOT_DIR}/.env" ]]; then
  umask 077
  postgres_password="$(openssl rand -hex 24)"
  minio_password="$(openssl rand -hex 24)"
  cat >"${ROOT_DIR}/.env" <<EOF
POSTGRES_DB=taxi_warehouse
POSTGRES_USER=taxi_app
POSTGRES_PASSWORD=${postgres_password}
DATABASE_URL=postgresql+psycopg://taxi_app:${postgres_password}@127.0.0.1:5432/taxi_warehouse
MINIO_ACCESS_KEY=taxi_admin
MINIO_SECRET_KEY=${minio_password}
EOF
fi
set -a
source "${ROOT_DIR}/.env"
set +a
for required_name in POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD DATABASE_URL MINIO_SECRET_KEY; do
  [[ -n "${!required_name:-}" ]] || { log_error "Missing ${required_name} in .env"; exit 1; }
done

docker compose --project-name nyc-taxi-a1 --env-file "${ROOT_DIR}/.env" \
  --file "${ROOT_DIR}/infra/local/compose.postgres.yaml" up --detach --wait postgres
"${ROOT_DIR}/scripts/download-sources.sh"
DATABASE_URL="${DATABASE_URL}" "${ROOT_DIR}/.venv/bin/alembic" -c "${ROOT_DIR}/alembic.ini" upgrade head

export AIRFLOW_HOME="${ROOT_DIR}/.local/airflow"
export AIRFLOW__CORE__DAGS_FOLDER="${ROOT_DIR}/airflow/dags"
export AIRFLOW__CORE__LOAD_EXAMPLES=false
export AIRFLOW__CORE__EXECUTOR=SequentialExecutor
export AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=false
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="sqlite:///${AIRFLOW_HOME}/airflow.db"
export AIRFLOW__CORE__FERNET_KEY=""
export PYTHONPATH="${ROOT_DIR}"
mkdir -p "${AIRFLOW_HOME}" "${ROOT_DIR}/.local/logs"
"${ROOT_DIR}/.venv/bin/airflow" db migrate
"${ROOT_DIR}/.venv/bin/airflow" pools set taxi_etl_pool 1 "Sequential local ETL"
"${ROOT_DIR}/.venv/bin/airflow" dags list | grep -Fq taxi_monthly_etl || { log_error "Airflow DAG import failed"; exit 1; }

for month in 2023-01 2023-02; do
  execution_date="${month}-05T06:00:00+00:00"
  log_info "Airflow ETL: ${month}"
  "${ROOT_DIR}/.venv/bin/airflow" dags test taxi_monthly_etl "${execution_date}" \
    --conf "{\"source_month\":\"${month}\"}" 2>&1 | tee "${ROOT_DIR}/.local/logs/airflow-${month}.log"
done

"${ROOT_DIR}/.venv/bin/python" - <<'PY'
import os

import psycopg

url = os.environ["DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://")
with psycopg.connect(url) as conn:
    rows = dict(conn.execute("""
        SELECT left(pickup_date_key::text, 6), count(*)
        FROM warehouse.fact_taxi_trips GROUP BY 1 ORDER BY 1
    "").fetchall())
    assert rows.keys() == {"202301", "202302"}, rows
    assert all(count > 1_000_000 for count in rows.values()), rows
    dashboard_rows = conn.execute("SELECT coalesce(sum(trip_count), 0) FROM analytics.dashboard_trip_metrics").fetchone()[0]
    assert dashboard_rows == sum(rows.values()), (dashboard_rows, rows)
    unknown_zones = conn.execute("SELECT count(*) FROM warehouse.fact_taxi_trips WHERE pickup_zone_key = 0").fetchone()[0]
    assert unknown_zones == 0, unknown_zones
print(f"Warehouse verified: {rows}; total={sum(rows.values()):,}")
PY

log_success "Local Assignment 1 demo is ready"
log_info "PostgreSQL: 127.0.0.1:5432"
log_info "Teardown: bash ./teardown.sh --local"
if [[ "${NO_DASHBOARD}" == true ]]; then
  exit 0
fi
log_info "Dashboard: http://localhost:8501 (Ctrl-C stops Streamlit; PostgreSQL remains available)"
exec "${ROOT_DIR}/.venv/bin/streamlit" run "${ROOT_DIR}/dashboard/app.py" \
  --server.address 0.0.0.0 --server.port 8501 --server.headless true
