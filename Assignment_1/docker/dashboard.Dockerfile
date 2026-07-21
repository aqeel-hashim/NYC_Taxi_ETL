FROM python:3.12-slim

RUN useradd --create-home --uid 10001 appuser
WORKDIR /app

COPY README.md pyproject.toml uv.lock /app/
COPY dashboard/ /app/dashboard/
COPY src/ /app/src/

RUN pip install --no-cache-dir -e /app "streamlit>=1.40" "psycopg[binary]>=3.2" "polars>=1.0" "pyarrow>=17.0"

USER appuser
EXPOSE 8501
CMD ["streamlit", "run", "dashboard/app.py", "--server.port=8501", "--server.address=0.0.0.0"]
