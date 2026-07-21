"""MinIO S3-compatible client wrapper with local fallback."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import polars as pl


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


def quarantine_rejected(rejected: pl.DataFrame, source_month: str, base_dir: str = "data/quarantine") -> str:
    """Save rejected rows as Parquet to local disk (MinIO fallback)."""
    path = os.path.join(base_dir, source_month)
    Path(path).mkdir(parents=True, exist_ok=True)
    filepath = os.path.join(path, "rejected.parquet")
    if len(rejected):
        rejected.write_parquet(filepath)
    else:
        Path(filepath).touch()
    return filepath
