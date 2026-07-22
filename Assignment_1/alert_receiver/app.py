from __future__ import annotations

import json
import os
import re
import secrets
from datetime import UTC, datetime
from html import escape
from pathlib import Path
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import HTMLResponse

app = FastAPI(title="taxi-alert-receiver")
_SENSITIVE_KEY = re.compile(r"password|secret|token|authorization|cookie|credential|api[-_]?key", re.I)
_SENSITIVE_VALUE = re.compile(
    r"(?i)\b(password|secret|token|authorization|cookie|credential|api[-_]?key)\s*[:=]\s*[^\s,;}]+"
)
_SAFE_FIELDS = {
    "alertname",
    "alerts",
    "commonLabels",
    "dag_id",
    "endsAt",
    "event",
    "exception_class",
    "fingerprint",
    "groupKey",
    "groupLabels",
    "labels",
    "namespace",
    "pod",
    "receiver",
    "run_id",
    "service",
    "severity",
    "source_month",
    "startsAt",
    "status",
    "task_id",
    "truncatedAlerts",
    "try_number",
}


def _alert_dir() -> Path:
    return Path(os.environ.get("ALERT_STORAGE_DIR", "data/alerts"))


def _sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        sanitized: dict[str, Any] = {}
        for key, item in value.items():
            name = str(key)
            if _SENSITIVE_KEY.search(name):
                sanitized[name] = "[REDACTED]"
            elif name in _SAFE_FIELDS:
                sanitized[name] = _sanitize(item)
            else:
                sanitized[name] = "[OMITTED]"
        return sanitized
    if isinstance(value, list):
        return [_sanitize(item) for item in value]
    if isinstance(value, str):
        return _SENSITIVE_VALUE.sub(lambda match: f"{match.group(1)}=[REDACTED]", value)[:4000]
    if value is None or isinstance(value, bool | int | float):
        return value
    return str(value)[:4000]


def _records() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for path in sorted(_alert_dir().glob("*.json"), reverse=True)[:100]:
        try:
            records.append(json.loads(path.read_text()))
        except (OSError, json.JSONDecodeError):
            continue
    return records


@app.post("/webhook")
async def webhook(
    request: Request,
    authorization: str | None = Header(default=None),
    x_webhook_token: str | None = Header(default=None),
) -> dict[str, object]:
    expected_token = os.environ.get("ALERT_WEBHOOK_TOKEN")
    if not expected_token:
        raise HTTPException(status_code=503, detail="webhook token is not configured")
    bearer_token = authorization.removeprefix("Bearer ") if authorization else None
    supplied_token = x_webhook_token or bearer_token
    if supplied_token is None or not secrets.compare_digest(supplied_token, expected_token):
        raise HTTPException(status_code=401, detail="invalid webhook token")
    body = await request.json()
    alert_id = f"{datetime.now(UTC).strftime('%Y%m%d%H%M%S%f')}-{uuid4().hex}"
    alert_dir = _alert_dir()
    alert_dir.mkdir(parents=True, exist_ok=True)
    record = {
        "id": alert_id,
        "received_at": datetime.now(UTC).isoformat(),
        "payload": _sanitize(body),
    }
    path = alert_dir / f"{alert_id}.json"
    temporary_path = path.with_suffix(".tmp")
    temporary_path.write_text(json.dumps(record, indent=2, sort_keys=True))
    temporary_path.replace(path)
    return {"status": "received", "id": alert_id}


@app.get("/", response_class=HTMLResponse)
async def index() -> str:
    rows = "".join(
        f"<tr><td>{escape(str(record['received_at']))}</td>"
        f"<td><pre>{escape(json.dumps(record['payload'], sort_keys=True))}</pre></td></tr>"
        for record in _records()
    )
    return (
        "<!doctype html><html><head><title>Taxi alerts</title></head><body>"
        "<h1>Sanitized alert receipts</h1><table><thead><tr><th>Received</th><th>Payload</th></tr></thead>"
        f"<tbody>{rows}</tbody></table></body></html>"
    )


@app.get("/api/events")
async def events() -> list[dict[str, Any]]:
    return _records()


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
