from __future__ import annotations

import os
from dataclasses import dataclass
from decimal import Decimal

import polars as pl
import psycopg


@dataclass(frozen=True)
class DashboardData:
    average_fare: pl.DataFrame
    peak_hours: pl.DataFrame
    revenue: pl.DataFrame


def load_dashboard_data(month: str, database_url: str | None = None) -> DashboardData:
    start_key, end_key = month_bounds(month)
    url = database_url or os.environ["DATABASE_URL"]
    with psycopg.connect(url.replace("postgresql+psycopg://", "postgresql://"), autocommit=True) as conn:
        return DashboardData(
            average_fare=_query(
                conn,
                """
                SELECT pickup_date_key, avg_fare_per_mile_dollars
                FROM (
                    SELECT pickup_date_key,
                        ROUND(10.0 * SUM(fare_amount_cents)::numeric
                            / NULLIF(SUM(distance_millimiles), 0), 2) AS avg_fare_per_mile_dollars
                    FROM warehouse.fact_taxi_trips
                    WHERE NOT has_statistical_outlier
                        AND pickup_date_key >= %(start_key)s AND pickup_date_key < %(end_key)s
                    GROUP BY pickup_date_key
                ) AS daily
                ORDER BY pickup_date_key
                """,
                {"start_key": start_key, "end_key": end_key},
            ),
            peak_hours=_query(
                conn,
                """
                SELECT t.hour AS pickup_hour, t.daypart,
                    LPAD(t.hour::text, 2, '0') || ':00' AS hour_label,
                    COUNT(*) AS trip_count
                FROM warehouse.fact_taxi_trips AS f
                INNER JOIN warehouse.dim_time AS t ON f.pickup_time_key = t.time_key
                WHERE f.pickup_date_key >= %(start_key)s AND f.pickup_date_key < %(end_key)s
                GROUP BY t.hour, t.daypart
                ORDER BY trip_count DESC
                """,
                {"start_key": start_key, "end_key": end_key},
            ),
            revenue=_query(
                conn,
                """
                SELECT p.business_key AS payment_type_key, p.label AS payment_type_label,
                    ROUND(SUM(f.total_amount_cents)::numeric / 100.0, 2) AS total_revenue_dollars,
                    COUNT(*) AS trip_count,
                    ROUND(AVG(f.total_amount_cents)::numeric / 100.0, 2) AS avg_revenue_per_trip_dollars
                FROM warehouse.fact_taxi_trips AS f
                INNER JOIN warehouse.dim_payment_type AS p ON f.payment_type_key = p.surrogate_key
                WHERE NOT f.has_statistical_outlier
                    AND f.pickup_date_key >= %(start_key)s AND f.pickup_date_key < %(end_key)s
                GROUP BY p.business_key, p.label
                ORDER BY total_revenue_dollars DESC
                """,
                {"start_key": start_key, "end_key": end_key},
            ),
        )


def month_bounds(month: str) -> tuple[int, int]:
    year = int(month[:4])
    month_number = int(month[5:7])
    start = year * 10000 + month_number * 100 + 1
    if month_number == 12:
        return start, (year + 1) * 10000 + 101
    return start, year * 10000 + (month_number + 1) * 100 + 1


def decimal_to_float(value: object) -> float:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, int | float):
        return float(value)
    return 0.0


def _query(conn: psycopg.Connection[tuple[object, ...]], sql: str, params: dict[str, object]) -> pl.DataFrame:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        columns = [desc[0] for desc in cur.description] if cur.description else []
    return pl.DataFrame(rows, schema=columns, orient="row")
