from math import nan

import pytest

from nyc_taxi_etl.storage import minio
from nyc_taxi_etl.transform.conversions import dollars_to_cents, miles_to_millimiles, seconds_between


def test_scalar_conversions() -> None:
    assert dollars_to_cents(1.235) == 124
    assert dollars_to_cents(nan) is None
    assert miles_to_millimiles(1.25) == 1250
    assert seconds_between(10.0, 25.4) == 15
    assert seconds_between(None, 25.4) is None


def test_optional_minio_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    minio._client = None
    monkeypatch.delenv("MINIO_ENDPOINT", raising=False)
    assert minio.get_client() is None

    monkeypatch.setenv("MINIO_ENDPOINT", "http://minio:9000")
    monkeypatch.setenv("MINIO_ACCESS_KEY", "access")
    monkeypatch.setenv("MINIO_SECRET_KEY", "secret")
    client = minio.get_client()
    assert client is not None
    assert (client.endpoint, client.access_key, client.secret_key) == ("http://minio:9000", "access", "secret")
