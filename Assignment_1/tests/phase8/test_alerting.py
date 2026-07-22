from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from nyc_taxi_etl.alerting import _payload, _post_webhook, _send_email


def test_failure_payload_excludes_exception_message() -> None:
    payload = _payload(
        {
            "task_instance": SimpleNamespace(dag_id="taxi", task_id="load", try_number=2),
            "run_id": "scheduled__2026-01-01",
            "exception": RuntimeError("password=do-not-leak"),
        }
    )

    assert payload == {
        "event": "airflow_task_failed",
        "dag_id": "taxi",
        "run_id": "scheduled__2026-01-01",
        "task_id": "load",
        "try_number": 2,
        "exception_class": "RuntimeError",
    }


def test_webhook_uses_secret_header(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ALERT_WEBHOOK_URL", "http://alerts/webhook")
    monkeypatch.setenv("ALERT_WEBHOOK_TOKEN", "generated-token")
    post = MagicMock()
    post.return_value.raise_for_status.return_value = None
    monkeypatch.setattr("nyc_taxi_etl.alerting.requests.post", post)

    _post_webhook({"event": "failure"})

    post.assert_called_once_with(
        "http://alerts/webhook",
        json={"event": "failure"},
        headers={"X-Webhook-Token": "generated-token"},
        timeout=10,
    )


def test_smtp_relay_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SMTP_HOST", "smtp.example.test")
    monkeypatch.setenv("SMTP_PORT", "2525")
    monkeypatch.setenv("SMTP_USERNAME", "relay-user")
    monkeypatch.setenv("SMTP_PASSWORD", "relay-password")
    smtp = MagicMock()
    smtp.return_value.__enter__.return_value = smtp
    monkeypatch.setattr("nyc_taxi_etl.alerting.smtplib.SMTP", smtp)

    _send_email({"dag_id": "taxi", "task_id": "load"})

    smtp.assert_called_once_with("smtp.example.test", 2525, timeout=10.0)
    smtp.login.assert_called_once_with("relay-user", "relay-password")
    smtp.send_message.assert_called_once()
