"""Storage package for MinIO/local file operations."""

from nyc_taxi_etl.storage.minio import MinioClient, get_client

__all__ = ["MinioClient", "get_client"]
