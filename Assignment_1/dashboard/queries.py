from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from typing import Any

import polars as pl
import psycopg
from psycopg import Connection

from dashboard.state import Cursor, DashboardFilters, ExplorerFilters, FilterOptions, Option

PAGE_SIZE = 100


@dataclass(frozen=True)
class DashboardData:
    kpis: pl.DataFrame
    comparison_kpis: pl.DataFrame
    daily: pl.DataFrame
    hourly: pl.DataFrame
    heatmap: pl.DataFrame
    zones: pl.DataFrame
    comparison_zones: pl.DataFrame
    payments: pl.DataFrame
    comparison_payments: pl.DataFrame
    vendors: pl.DataFrame
    comparison_vendors: pl.DataFrame
    rates: pl.DataFrame
    comparison_rates: pl.DataFrame
    components: pl.DataFrame
    publications: pl.DataFrame
    quality: pl.DataFrame
    fingerprints: pl.DataFrame
    thresholds: pl.DataFrame
    alerts: pl.DataFrame


@dataclass(frozen=True)
class ExplorerPage:
    rows: pl.DataFrame
    has_more: bool


def warehouse_version(database_url: str | None = None) -> str:
    with _connect(database_url) as conn:
        row = conn.execute(
            "SELECT COALESCE(MAX(warehouse_version), '0') FROM analytics.dashboard_publication_state"
        ).fetchone()
    return str(row[0]) if row and row[0] is not None else "0"


def load_filter_options(warehouse_version_key: str, database_url: str | None = None) -> FilterOptions:
    del warehouse_version_key
    with _connect(database_url) as conn:
        coverage = conn.execute(
            "SELECT MIN(pickup_date), MAX(pickup_date) FROM analytics.dashboard_trip_metrics"
        ).fetchone()
        zones = _option_rows(
            conn,
            """
            SELECT DISTINCT pickup_zone_key, pickup_zone_label
            FROM analytics.dashboard_trip_metrics
            ORDER BY pickup_zone_label, pickup_zone_key
            """,
        )
        payments = _option_rows(
            conn,
            """
            SELECT DISTINCT payment_type_key, payment_type_label
            FROM analytics.dashboard_trip_metrics
            ORDER BY payment_type_label, payment_type_key
            """,
        )
        vendors = _option_rows(
            conn,
            """
            SELECT DISTINCT vendor_key, vendor_label
            FROM analytics.dashboard_trip_metrics
            ORDER BY vendor_label, vendor_key
            """,
        )
        rates = _option_rows(
            conn,
            """
            SELECT DISTINCT rate_code_key, rate_code_label
            FROM analytics.dashboard_trip_metrics
            ORDER BY rate_code_label, rate_code_key
            """,
        )
        borough_rows = conn.execute(
            """
            SELECT DISTINCT pickup_borough
            FROM analytics.dashboard_trip_metrics
            WHERE pickup_borough IS NOT NULL
            ORDER BY pickup_borough
            """
        ).fetchall()

    if not coverage or not isinstance(coverage[0], date) or not isinstance(coverage[1], date):
        raise ValueError("No published taxi data are available. Run the ETL pipeline, then refresh.")
    minimum = coverage[0]
    maximum = coverage[1]
    return FilterOptions(
        minimum_date=minimum,
        maximum_date=maximum,
        boroughs=tuple(str(row[0]) for row in borough_rows),
        zones=zones,
        payments=payments,
        vendors=vendors,
        rates=rates,
    )


def load_dashboard_data(
    filters: DashboardFilters,
    comparison: DashboardFilters,
    warehouse_version_key: str,
    database_url: str | None = None,
) -> DashboardData:
    del warehouse_version_key
    with _connect(database_url) as conn:
        current_where, current_params = _metric_where(filters)
        comparison_where, comparison_params = _metric_where(comparison)
        return DashboardData(
            kpis=_query(conn, _kpi_sql(current_where, filters.include_outliers), current_params),
            comparison_kpis=_query(
                conn,
                _kpi_sql(comparison_where, comparison.include_outliers),
                comparison_params,
            ),
            daily=_query(conn, _daily_sql(current_where, filters.include_outliers), current_params),
            hourly=_query(conn, _hourly_sql(current_where, filters.include_outliers), current_params),
            heatmap=_query(conn, _heatmap_sql(current_where), current_params),
            zones=_query(conn, _zones_sql(current_where, filters.include_outliers), current_params),
            comparison_zones=_query(
                conn,
                _zones_sql(comparison_where, comparison.include_outliers),
                comparison_params,
            ),
            payments=_query(
                conn,
                _breakdown_sql(current_where, "payment_type", filters.include_outliers),
                current_params,
            ),
            comparison_payments=_query(
                conn,
                _breakdown_sql(comparison_where, "payment_type", comparison.include_outliers),
                comparison_params,
            ),
            vendors=_query(conn, _breakdown_sql(current_where, "vendor", filters.include_outliers), current_params),
            comparison_vendors=_query(
                conn,
                _breakdown_sql(comparison_where, "vendor", comparison.include_outliers),
                comparison_params,
            ),
            rates=_query(conn, _breakdown_sql(current_where, "rate_code", filters.include_outliers), current_params),
            comparison_rates=_query(
                conn,
                _breakdown_sql(comparison_where, "rate_code", comparison.include_outliers),
                comparison_params,
            ),
            components=_query(conn, _components_sql(current_where, filters.include_outliers), current_params),
            publications=_query(
                conn,
                """
                SELECT * FROM analytics.dashboard_publication_state
                WHERE source_month BETWEEN %(start_month)s AND %(end_month)s
                ORDER BY source_month DESC
                """,
                {
                    "start_month": filters.start_date.strftime("%Y-%m"),
                    "end_month": filters.end_date.strftime("%Y-%m"),
                },
            ),
            quality=_query(
                conn,
                """
                SELECT * FROM analytics.dashboard_quality_summary
                WHERE source_month BETWEEN %(start_month)s AND %(end_month)s
                ORDER BY row_count DESC, issue_code
                """,
                {
                    "start_month": filters.start_date.strftime("%Y-%m"),
                    "end_month": filters.end_date.strftime("%Y-%m"),
                },
            ),
            fingerprints=_query(conn, "SELECT * FROM analytics.dashboard_fingerprints ORDER BY source_month DESC", {}),
            thresholds=_query(conn, "SELECT * FROM analytics.dashboard_thresholds ORDER BY source_month DESC", {}),
            alerts=_query(conn, "SELECT * FROM analytics.dashboard_alerts ORDER BY occurred_at DESC LIMIT 20", {}),
        )


def load_explorer_page(
    filters: DashboardFilters,
    explorer: ExplorerFilters,
    cursor: Cursor | None = None,
    direction: str = "next",
    database_url: str | None = None,
) -> ExplorerPage:
    if direction not in {"next", "previous"}:
        raise ValueError("explorer direction must be 'next' or 'previous'")

    where, params = _explorer_where(filters, explorer)
    operator, order = (">", "ASC") if direction == "next" else ("<", "DESC")
    if cursor is not None:
        where += f" AND (x.pickup_at_local, x.trip_key) {operator} (%(cursor_time)s, %(cursor_key)s)"
        params.update(cursor_time=cursor.pickup_at_local, cursor_key=cursor.trip_key)
    params["limit"] = PAGE_SIZE + 1

    with _connect(database_url) as conn:
        rows = _query(
            conn,
            f"""
            SELECT pickup_at_local, trip_key, dropoff_at_local,
                pickup_zone_label, dropoff_zone_label, payment_type_label, vendor_label, rate_code_label,
                passenger_count, distance_miles, duration_minutes, fare_amount_dollars,
                tip_amount_dollars, total_amount_dollars, has_statistical_outlier, has_quality_issue
            FROM analytics.dashboard_trip_explorer AS x
            WHERE {where}
            ORDER BY x.pickup_at_local {order}, x.trip_key {order}
            LIMIT %(limit)s
            """,
            params,
        )

    has_more = len(rows) > PAGE_SIZE
    rows = rows.head(PAGE_SIZE)
    if direction == "previous":
        rows = rows.reverse()
    return ExplorerPage(rows=rows, has_more=has_more)


def decimal_to_float(value: object) -> float:
    if isinstance(value, Decimal | int | float):
        return float(value)
    return 0.0


def _connect(database_url: str | None) -> Connection[tuple[Any, ...]]:
    url = (database_url or os.environ["DATABASE_URL"]).replace("postgresql+psycopg://", "postgresql://")
    return psycopg.connect(
        url,
        autocommit=True,
        options="-c statement_timeout=1500 -c default_transaction_read_only=on",
    )


def _option_rows(conn: Connection[tuple[Any, ...]], sql: str) -> tuple[Option, ...]:
    return tuple(Option(key=int(row[0]), label=str(row[1])) for row in conn.execute(sql).fetchall())


def _metric_where(filters: DashboardFilters, alias: str = "m") -> tuple[str, dict[str, object]]:
    if alias == "x":
        clauses = [f"{alias}.pickup_at_local >= %(start_time)s AND {alias}.pickup_at_local < %(end_time)s"]
        params: dict[str, object] = {
            "start_time": datetime.combine(filters.start_date, time.min),
            "end_time": datetime.combine(filters.end_date + timedelta(days=1), time.min),
        }
    else:
        clauses = [f"{alias}.pickup_date_key BETWEEN %(start_date_key)s AND %(end_date_key)s"]
        params = {
            "start_date_key": int(filters.start_date.strftime("%Y%m%d")),
            "end_date_key": int(filters.end_date.strftime("%Y%m%d")),
        }
    for values, column, parameter in (
        (filters.boroughs, "pickup_borough", "boroughs"),
        (filters.zone_keys, "pickup_zone_key", "zone_keys"),
        (filters.payment_keys, "payment_type_key", "payment_keys"),
        (filters.vendor_keys, "vendor_key", "vendor_keys"),
        (filters.rate_keys, "rate_code_key", "rate_keys"),
    ):
        if values:
            clauses.append(f"{alias}.{column} = ANY(%({parameter})s)")
            params[parameter] = list(values)
    return " AND ".join(clauses), params


def _explorer_where(filters: DashboardFilters, explorer: ExplorerFilters) -> tuple[str, dict[str, object]]:
    where, params = _metric_where(filters, alias="x")
    clauses = [where]
    if explorer.dropoff_zone_keys:
        clauses.append("x.dropoff_zone_key = ANY(%(dropoff_zone_keys)s)")
        params["dropoff_zone_keys"] = list(explorer.dropoff_zone_keys)
    if explorer.quality_only:
        clauses.append("x.has_quality_issue")
    for value, column, parameter, scale in (
        (explorer.minimum_distance_miles, "distance_millimiles", "minimum_distance", 1000),
        (explorer.maximum_distance_miles, "distance_millimiles", "maximum_distance", 1000),
        (explorer.minimum_duration_minutes, "duration_seconds", "minimum_duration", 60),
        (explorer.maximum_duration_minutes, "duration_seconds", "maximum_duration", 60),
        (explorer.minimum_total_dollars, "total_amount_cents", "minimum_total", 100),
        (explorer.maximum_total_dollars, "total_amount_cents", "maximum_total", 100),
    ):
        if value is None:
            continue
        operator = ">=" if parameter.startswith("minimum") else "<="
        clauses.append(f"x.{column} {operator} %({parameter})s")
        params[parameter] = round(value * scale)
    return " AND ".join(clauses), params


def _financial_condition(include_outliers: bool, alias: str = "m") -> str:
    return "TRUE" if include_outliers else f"NOT {alias}.has_statistical_outlier"


def _kpi_sql(where: str, include_outliers: bool) -> str:
    financial = _financial_condition(include_outliers)
    return f"""
        SELECT
            COALESCE(SUM(m.trip_count), 0) AS trip_count,
            COALESCE(SUM(m.total_amount_cents_sum) FILTER (WHERE {financial}), 0)::numeric / 100.0
                AS gross_revenue_dollars,
            SUM(m.total_amount_cents_sum) FILTER (WHERE {financial})::numeric
                / NULLIF(100.0 * SUM(m.trip_count) FILTER (WHERE {financial}), 0)
                AS revenue_per_trip_dollars,
            10.0 * SUM(m.fare_amount_cents_sum) FILTER (WHERE {financial})::numeric
                / NULLIF(SUM(m.distance_millimiles_sum) FILTER (WHERE {financial}), 0)
                AS fare_per_mile_dollars,
            SUM(m.duration_seconds_sum) FILTER (WHERE {financial})::numeric
                / NULLIF(60.0 * SUM(m.trip_count) FILTER (WHERE {financial}), 0)
                AS average_duration_minutes,
            100.0 * SUM(m.tip_amount_cents_sum) FILTER (
                    WHERE m.payment_type_key = 1 AND {financial}
                )::numeric
                / NULLIF(SUM(m.fare_amount_cents_sum) FILTER (
                    WHERE m.payment_type_key = 1 AND {financial}
                ), 0) AS recorded_card_tip_rate
        FROM analytics.dashboard_trip_metrics AS m
        WHERE {where}
    """


def _daily_sql(where: str, include_outliers: bool) -> str:
    financial = _financial_condition(include_outliers)
    return f"""
        SELECT m.pickup_date,
            SUM(m.trip_count) AS trip_count,
            SUM(m.total_amount_cents_sum) FILTER (WHERE {financial})::numeric / 100.0
                AS gross_revenue_dollars,
            10.0 * SUM(m.fare_amount_cents_sum) FILTER (WHERE {financial})::numeric
                / NULLIF(SUM(m.distance_millimiles_sum) FILTER (WHERE {financial}), 0)
                AS fare_per_mile_dollars
        FROM analytics.dashboard_trip_metrics AS m
        WHERE {where}
        GROUP BY m.pickup_date
        ORDER BY m.pickup_date
    """


def _hourly_sql(where: str, include_outliers: bool) -> str:
    financial = _financial_condition(include_outliers)
    return f"""
        SELECT m.pickup_hour,
            SUM(m.trip_count) AS trip_count,
            3.6 * SUM(m.distance_millimiles_sum) FILTER (WHERE {financial})::numeric
                / NULLIF(SUM(m.duration_seconds_sum) FILTER (WHERE {financial}), 0)
                AS weighted_network_speed_mph
        FROM analytics.dashboard_trip_metrics AS m
        WHERE {where}
        GROUP BY m.pickup_hour
        ORDER BY m.pickup_hour
    """


def _heatmap_sql(where: str) -> str:
    return f"""
        SELECT m.weekday_number, m.weekday_name, m.pickup_hour, SUM(m.trip_count) AS trip_count
        FROM analytics.dashboard_trip_metrics AS m
        WHERE {where}
        GROUP BY m.weekday_number, m.weekday_name, m.pickup_hour
        ORDER BY m.weekday_number, m.pickup_hour
    """


def _zones_sql(where: str, include_outliers: bool) -> str:
    financial = _financial_condition(include_outliers)
    return f"""
        SELECT m.pickup_zone_key, m.pickup_zone_label, m.pickup_borough,
            SUM(m.trip_count) AS trip_count,
            SUM(m.total_amount_cents_sum) FILTER (WHERE {financial})::numeric / 100.0
                AS gross_revenue_dollars,
            SUM(m.total_amount_cents_sum) FILTER (WHERE {financial})::numeric
                / NULLIF(100.0 * SUM(m.trip_count) FILTER (WHERE {financial}), 0)
                AS revenue_per_trip_dollars,
            10.0 * SUM(m.fare_amount_cents_sum) FILTER (WHERE {financial})::numeric
                / NULLIF(SUM(m.distance_millimiles_sum) FILTER (WHERE {financial}), 0)
                AS fare_per_mile_dollars
        FROM analytics.dashboard_trip_metrics AS m
        WHERE {where}
        GROUP BY m.pickup_zone_key, m.pickup_zone_label, m.pickup_borough
        ORDER BY trip_count DESC
    """


def _breakdown_sql(where: str, dimension: str, include_outliers: bool) -> str:
    if dimension not in {"payment_type", "vendor", "rate_code"}:
        raise ValueError("unsupported breakdown dimension")
    financial = _financial_condition(include_outliers)
    return f"""
        SELECT m.{dimension}_key, m.{dimension}_label,
            SUM(m.total_amount_cents_sum)::numeric / 100.0 AS gross_revenue_dollars,
            SUM(m.trip_count) AS trip_count,
            SUM(m.total_amount_cents_sum)::numeric / NULLIF(100.0 * SUM(m.trip_count), 0)
                AS revenue_per_trip_dollars,
            100.0 * SUM(m.tip_amount_cents_sum) FILTER (WHERE m.payment_type_key = 1)::numeric
                / NULLIF(SUM(m.fare_amount_cents_sum) FILTER (WHERE m.payment_type_key = 1), 0)
                AS recorded_card_tip_rate
        FROM analytics.dashboard_trip_metrics AS m
        WHERE {where} AND {financial}
        GROUP BY m.{dimension}_key, m.{dimension}_label
        ORDER BY gross_revenue_dollars DESC
    """


def _components_sql(where: str, include_outliers: bool) -> str:
    financial = _financial_condition(include_outliers)
    return f"""
        SELECT
            SUM(m.fare_amount_cents_sum)::numeric / 100.0 AS fare,
            SUM(m.extra_cents_sum)::numeric / 100.0 AS extra,
            SUM(m.mta_tax_cents_sum)::numeric / 100.0 AS mta_tax,
            SUM(m.tip_amount_cents_sum)::numeric / 100.0 AS tips,
            SUM(m.tolls_amount_cents_sum)::numeric / 100.0 AS tolls,
            SUM(m.improvement_surcharge_cents_sum)::numeric / 100.0 AS improvement_surcharge,
            SUM(m.congestion_surcharge_cents_sum)::numeric / 100.0 AS congestion_surcharge,
            SUM(m.airport_fee_cents_sum)::numeric / 100.0 AS airport_fee
        FROM analytics.dashboard_trip_metrics AS m
        WHERE {where} AND {financial}
    """


def _query(conn: Connection[tuple[Any, ...]], sql: str, params: dict[str, object]) -> pl.DataFrame:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        columns = [desc[0] for desc in cur.description] if cur.description else []
    return pl.DataFrame(rows, schema=columns, orient="row")
