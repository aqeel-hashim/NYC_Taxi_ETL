FROM python:3.12.10-slim-bookworm

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY docker/alert-receiver.requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --require-hashes --timeout 300 --retries 10 -r requirements.txt \
    && addgroup --system --gid 10001 alert-receiver \
    && adduser --system --uid 10001 --ingroup alert-receiver alert-receiver

COPY --chown=10001:10001 alert_receiver/ alert_receiver/

USER 10001:10001

EXPOSE 8000

CMD ["uvicorn", "alert_receiver.app:app", "--host", "0.0.0.0", "--port", "8000"]
