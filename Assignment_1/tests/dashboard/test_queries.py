from __future__ import annotations

from decimal import Decimal
from pathlib import Path

from dashboard.queries import decimal_to_float, month_bounds


def test_month_bounds() -> None:
    assert month_bounds("2023-01") == (20230101, 20230201)
    assert month_bounds("2023-12") == (20231201, 20240101)


def test_decimal_to_float() -> None:
    assert decimal_to_float(Decimal("12.34")) == 12.34
    assert decimal_to_float(None) == 0.0


def test_no_embedded_database_password() -> None:
    source = Path("dashboard/queries.py").read_text()
    assert "password=" not in source
    assert "taxi_dev_password" not in source
