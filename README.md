# NYC Taxi Data Engineering Assessments

Implementation of both tasks in [`Docs/Data_Engineering_Assessments.docx.txt`](Docs/Data_Engineering_Assessments.docx.txt).

## Assignment 1: Batch ETL

Assignment 1 is the runnable release: two official NYC Yellow Taxi months, Apache Airflow orchestration, PostgreSQL star schema, structured quality logging, required SQL metrics, and a Streamlit dashboard.

```bash
cd Assignment_1
bash ./setup.sh --local-demo
```

The first run downloads about 96 MB of TLC Parquet data and processes 5,849,239 accepted trips. Open <http://localhost:8501> when setup prints that the dashboard is ready.

[Full prerequisites, architecture, expected results, and troubleshooting](Assignment_1/README.md)

![Assignment 1 desktop dashboard](Assignment_1/docs/images/dashboard-desktop.png)

## Assignment 2: Streaming

Assignment 2 is isolated under [`Assignment_2/`](Assignment_2/). Its Kafka stack and documentation are independent from the Assignment 1 release ZIP.

## Repository Layout

| Path | Purpose |
|---|---|
| `Assignment_1/` | Batch ETL implementation and evaluator documentation |
| `Assignment_2/` | Streaming implementation |
| `Docs/` | Original assessment text |
| `docs/` | Repository contributor/agent notes; not needed for evaluation |
