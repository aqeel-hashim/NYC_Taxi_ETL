# Assignment 1: Batch ETL

Implementation has not started. Follow the reviewed [implementation plan](docs/implementation-plan.md).

## Agreed Planning Assumptions

- Load NYC Yellow Taxi January-February 2023 by default.
- Use Airflow KubernetesExecutor on Docker-backed kind, PostgreSQL, Polars, MinIO, and Streamlit/Plotly.
- Average fare per mile means ratio of summed fare to summed distance, not average trip-level ratios.
- Revenue means summed `total_amount` for hard-valid, non-refund rows.
- Financial/unit metrics exclude statistical outliers by default; demand counts retain all hard-valid rows.
- Peak hour means pickup trip count by local NYC wall-clock hour.
- Local hardware may use stage-by-stage service activation; multi-broker Kafka remains Assignment 2 work.
