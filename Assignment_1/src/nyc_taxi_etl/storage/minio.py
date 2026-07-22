"""MinIO connection settings for the optional extended platform."""

from __future__ import annotations

import os
from dataclasses import dataclass

from nyc_taxi_etl.storage.quarantine import quarantine_rejected


@dataclass
class MinioClient:
    endpoint: str
    access_key: str
    secret_key: str
    secure: bool = False
    bucket: str = "nyc-taxi-etl"


_client: MinioClient | None = None


def get_client() -> MinioClient | None:
    global _client
    if _client is None:
        endpoint = os.environ.get("MINIO_ENDPOINT", "")
        if not endpoint:
            return None
        _client = MinioClient(
            endpoint=endpoint,
            access_key=os.environ.get("MINIO_ACCESS_KEY", "minioadmin"),
            secret_key=os.environ.get("MINIO_SECRET_KEY", ""),
            secure=os.environ.get("MINIO_SECURE", "false").lower() == "true",
            bucket=os.environ.get("MINIO_BUCKET", "nyc-taxi-etl"),
        )
    return _client


__all__ = ["MinioClient", "get_client", "quarantine_rejected"]
