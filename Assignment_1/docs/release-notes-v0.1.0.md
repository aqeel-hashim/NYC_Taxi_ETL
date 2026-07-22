# Assignment 1 v0.1.0

## Highlights

- One-command fresh-machine demo: `bash ./setup.sh --local-demo`.
- Official January-February 2023 TLC data.
- 5,849,239 accepted trips in PostgreSQL monthly partitions.
- Apache Airflow orchestration with structured task and pipeline logs.
- Six-dimension star schema and aggregate analytics mart.
- Required average-fare-per-mile, peak-hour, and payment-revenue SQL.
- Responsive five-tab Streamlit/Plotly dashboard with official TLC zone geometry.
- Atomic/idempotent monthly fact, quality-detail, and quality-summary replacement.
- 95 automated tests and 86.31% branch coverage.

## Supported Evaluator Hosts

- glibc Linux x86_64/aarch64 and WSL2.
- Docker Engine/Desktop with Compose v2.
- 4 GiB RAM and 5 GiB free disk minimum.

Setup detects host commands but never invokes a distribution package manager or `sudo`. Alpine/musl automatic bootstrap is unsupported.

## Run

```bash
bash ./setup.sh --local-demo
```

Dashboard: <http://localhost:8501>

## Assets

`Assignment_1-v0.1.0.zip` contains only the Assignment 1 directory. Runtime data, secrets, caches, generated certificates, internal implementation plans, Assignment 2, and agent/editor files are excluded.

`Assignment_1-v0.1.0.zip.sha256` verifies the archive.

## Optional Scope

Kubernetes, OIDC, MinIO, Prometheus/Grafana/Loki, backup/restore, and AWS Terraform are included as extended architecture assets but are not required by the fresh-machine evaluator path.
