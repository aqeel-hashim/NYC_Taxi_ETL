from __future__ import annotations

import json
import logging
import os
import smtplib
import ssl
from collections.abc import Mapping
from email.message import EmailMessage
from typing import Any

import requests

from airflow.utils.context import Context

LOGGER = logging.getLogger(__name__)


def _payload(context: Mapping[str, Any]) -> dict[str, Any]:
    task_instance = context.get("task_instance")
    exception = context.get("exception")
    return {
        "event": "airflow_task_failed",
        "dag_id": getattr(task_instance, "dag_id", None),
        "run_id": context.get("run_id"),
        "task_id": getattr(task_instance, "task_id", None),
        "try_number": getattr(task_instance, "try_number", None),
        "exception_class": type(exception).__name__ if exception else None,
    }


def _post_webhook(payload: dict[str, Any]) -> None:
    url = os.environ.get("ALERT_WEBHOOK_URL")
    token = os.environ.get("ALERT_WEBHOOK_TOKEN")
    if not url or not token:
        return
    response = requests.post(url, json=payload, headers={"X-Webhook-Token": token}, timeout=10)
    response.raise_for_status()


def _send_email(payload: dict[str, Any]) -> None:
    host = os.environ.get("SMTP_HOST")
    if not host:
        return
    message = EmailMessage()
    message["Subject"] = f"Airflow failure: {payload['dag_id']}.{payload['task_id']}"
    message["From"] = os.environ.get("SMTP_FROM", "airflow@taxi.local")
    message["To"] = os.environ.get("ALERT_EMAIL_TO", "admin@taxi.local")
    message.set_content(json.dumps(payload, indent=2, sort_keys=True))

    port = int(os.environ.get("SMTP_PORT", "1025"))
    timeout = float(os.environ.get("SMTP_TIMEOUT", "10"))
    use_ssl = os.environ.get("SMTP_SSL", "false").lower() == "true"
    smtp_class = smtplib.SMTP_SSL if use_ssl else smtplib.SMTP
    with smtp_class(host, port, timeout=timeout) as smtp:
        if not use_ssl and os.environ.get("SMTP_STARTTLS", "false").lower() == "true":
            smtp.starttls(context=ssl.create_default_context())
        username = os.environ.get("SMTP_USERNAME")
        password = os.environ.get("SMTP_PASSWORD")
        if username and password:
            smtp.login(username, password)
        smtp.send_message(message)


def _push_failure_metric(payload: dict[str, Any]) -> None:
    url = os.environ.get("PUSHGATEWAY_URL")
    if not url:
        return
    # Fixed labels keep batch metrics bounded; run IDs and exception text stay in logs.
    body = 'taxi_batch_failures_total{source="airflow"} 1\n'
    response = requests.put(f"{url.rstrip('/')}/metrics/job/taxi_batch/outcome/failed", data=body, timeout=10)
    response.raise_for_status()


def notify_failure(context: Context) -> None:
    payload = _payload(context)
    for channel, callback in (("pushgateway", _push_failure_metric), ("webhook", _post_webhook), ("smtp", _send_email)):
        try:
            callback(payload)
        except Exception:
            LOGGER.exception("failure_notification_failed channel=%s", channel)
