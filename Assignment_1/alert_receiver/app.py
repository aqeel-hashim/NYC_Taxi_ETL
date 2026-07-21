from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from pathlib import Path

from fastapi import FastAPI, Request

app = FastAPI(title="taxi-alert-receiver")
ALERT_DIR = os.environ.get("ALERT_STORAGE_DIR", "data/alerts")


@app.post("/webhook")
async def webhook(request: Request) -> dict[str, object]:
    body = await request.json()
    alert_id = f"{datetime.now(UTC).strftime('%Y%m%d%H%M%S%f')}-{id(body)}"
    Path(ALERT_DIR).mkdir(parents=True, exist_ok=True)
    record = {
        "id": alert_id,
        "received_at": datetime.now(UTC).isoformat(),
        "payload": body,
        "headers": dict(request.headers),
    }
    path = Path(ALERT_DIR) / f"{alert_id}.json"
    path.write_text(json.dumps(record, indent=2, default=str))
    return {"status": "received", "id": alert_id}


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
