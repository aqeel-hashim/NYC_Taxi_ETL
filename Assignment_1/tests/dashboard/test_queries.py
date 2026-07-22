from __future__ import annotations

from collections.abc import Sequence
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

from dashboard import queries
from dashboard.state import Cursor, DashboardFilters, ExplorerFilters


def test_exact_ratio_of_sums_formulas_and_demand_policy() -> None:
    sql = queries._kpi_sql("m.pickup_date_key BETWEEN 1 AND 2", include_outliers=False)
    assert "10.0 * SUM(m.fare_amount_cents_sum)" in sql
    assert "/ NULLIF(SUM(m.distance_millimiles_sum)" in sql
    assert "100.0 * SUM(m.tip_amount_cents_sum)" in sql
    assert "m.payment_type_key = 1" in sql
    assert "COALESCE(SUM(m.trip_count), 0)" in sql
    assert "SUM(m.trip_count) FILTER (WHERE NOT m.has_statistical_outlier)" in sql


def test_filters_are_parameterized_and_prunable() -> None:
    filters = DashboardFilters(
        date(2023, 2, 1),
        date(2023, 2, 28),
        boroughs=("Queens",),
        zone_keys=(132,),
        payment_keys=(1,),
    )
    where, params = queries._metric_where(filters)
    assert "pickup_date_key BETWEEN %(start_date_key)s AND %(end_date_key)s" in where
    assert "= ANY(%(zone_keys)s)" in where
    assert params["start_date_key"] == 20230201
    assert params["zone_keys"] == [132]
    assert "Queens" not in where


def test_reverse_keyset_explorer_uses_allowlisted_order(monkeypatch: Any) -> None:
    rows = [
        (
            datetime(2023, 2, 1, 10, 0),
            1,
            datetime(2023, 2, 1, 10, 5),
            "A",
            "B",
            "Card",
            "V",
            "R",
            1,
            1,
            5,
            2,
            0,
            3,
            False,
            False,
        ),
        (
            datetime(2023, 2, 1, 11, 0),
            2,
            datetime(2023, 2, 1, 11, 5),
            "A",
            "B",
            "Card",
            "V",
            "R",
            1,
            1,
            5,
            2,
            0,
            3,
            False,
            False,
        ),
    ]
    connection = _FakeConnection(rows)
    monkeypatch.setattr(queries, "_connect", lambda _url: connection)
    filters = DashboardFilters(date(2023, 2, 1), date(2023, 2, 2))

    page = queries.load_explorer_page(
        filters,
        ExplorerFilters(),
        Cursor(datetime(2023, 2, 2), 99),
        direction="previous",
    )

    assert "(x.pickup_at_local, x.trip_key) < (%(cursor_time)s, %(cursor_key)s)" in connection.sql
    assert "ORDER BY x.pickup_at_local DESC, x.trip_key DESC" in connection.sql
    assert page.rows["trip_key"].to_list() == [2, 1]
    assert connection.params["limit"] == 101


def test_dashboard_queries_use_only_approved_analytics_interfaces() -> None:
    source = Path("dashboard/queries.py").read_text()
    assert "warehouse.fact_taxi_trips" not in source
    assert "ops." not in source
    assert "password=" not in source
    assert "warehouse_version_key" in source


def test_decimal_to_float() -> None:
    assert queries.decimal_to_float(Decimal("12.34")) == 12.34
    assert queries.decimal_to_float(None) == 0.0


class _FakeCursor:
    def __init__(self, connection: _FakeConnection) -> None:
        self.connection = connection
        self.description = [
            (name,)
            for name in (
                "pickup_at_local",
                "trip_key",
                "dropoff_at_local",
                "pickup_zone_label",
                "dropoff_zone_label",
                "payment_type_label",
                "vendor_label",
                "rate_code_label",
                "passenger_count",
                "distance_miles",
                "duration_minutes",
                "fare_amount_dollars",
                "tip_amount_dollars",
                "total_amount_dollars",
                "has_statistical_outlier",
                "has_quality_issue",
            )
        ]

    def __enter__(self) -> _FakeCursor:
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def execute(self, sql: str, params: dict[str, object]) -> None:
        self.connection.sql = sql
        self.connection.params = params

    def fetchall(self) -> list[tuple[object, ...]]:
        return self.connection.rows


class _FakeConnection:
    def __init__(self, rows: Sequence[tuple[object, ...]]) -> None:
        self.rows = list(rows)
        self.sql = ""
        self.params: dict[str, object] = {}

    def __enter__(self) -> _FakeConnection:
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def cursor(self) -> _FakeCursor:
        return _FakeCursor(self)
