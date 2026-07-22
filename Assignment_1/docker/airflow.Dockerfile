FROM apache/airflow:2.10.5-python3.12

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

USER airflow
COPY --chown=airflow:root README.md pyproject.toml uv.lock /opt/airflow/
COPY --chown=airflow:root src/ /opt/airflow/src/
COPY --chown=airflow:root airflow/dags/ /opt/airflow/dags/

RUN pip install --no-cache-dir "editables==0.5" "hatchling==1.26.3" "packaging>=23.2" \
    && pip install --no-cache-dir --no-build-isolation -e /opt/airflow/ \
    "apache-airflow-providers-fab==1.5.3" \
    "polars>=1.0" \
    "psycopg[binary]>=3.2" \
    "pyarrow>=17.0"
