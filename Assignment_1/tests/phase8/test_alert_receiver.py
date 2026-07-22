from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from alert_receiver.app import app


def test_webhook_requires_token_and_persists_sanitized_payload(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ALERT_STORAGE_DIR", str(tmp_path))
    monkeypatch.setenv("ALERT_WEBHOOK_TOKEN", "expected-token")
    client = TestClient(app)

    assert client.post("/webhook", json={"event": "failure"}).status_code == 401
    response = client.post(
        "/webhook",
        headers={"X-Webhook-Token": "expected-token", "Authorization": "Bearer must-not-persist"},
        json={
            "event": "failure",
            "password": "must-not-persist",
            "nested": {"api_key": "must-not-persist", "detail": "token=must-not-persist"},
        },
    )

    assert response.status_code == 200
    stored = json.loads(next(tmp_path.glob("*.json")).read_text())
    assert "headers" not in stored
    assert stored["payload"]["password"] == "[REDACTED]"
    assert stored["payload"]["nested"] == "[OMITTED]"
    assert "must-not-persist" not in json.dumps(stored)
    assert client.get("/api/events").json() == [stored]
    assert "Sanitized alert receipts" in client.get("/").text


def test_webhook_fails_closed_without_configured_token(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ALERT_STORAGE_DIR", str(tmp_path))
    monkeypatch.delenv("ALERT_WEBHOOK_TOKEN", raising=False)

    response = TestClient(app).post("/webhook", headers={"X-Webhook-Token": "anything"}, json={})

    assert response.status_code == 503
    assert not list(tmp_path.iterdir())
