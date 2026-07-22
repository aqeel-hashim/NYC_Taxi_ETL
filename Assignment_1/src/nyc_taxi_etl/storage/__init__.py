"""Local ETL output storage."""

from nyc_taxi_etl.storage.minio import MinioClient, get_client

__all__ = ["MinioClient", "get_client"]
