from __future__ import annotations

import logging
import os
import uuid
from datetime import date
from pathlib import Path

import polars as pl
import psycopg
import streamlit as st

from dashboard import queries
from dashboard.state import DashboardFilters, FilterOptions, Option, is_stale, prior_month_range
from dashboard.tabs import render_demand, render_explore, render_overview, render_quality, render_revenue

LOGGER = logging.getLogger(__name__)


def main() -> None:
    st.set_page_config(page_title="NYC Taxi Executive Brief", layout="wide")
    _theme()
    st.title("NYC Taxi Executive Brief")
    st.caption("Published Yellow Taxi demand, revenue, and quality. America/New_York local time.")

    try:
        version = queries.warehouse_version()
        options = _cached_filter_options(version)
        filters, comparison = _sidebar(options)
        with st.spinner("Reading published analytics..."):
            data = _cached_dashboard_data(filters, comparison, version)
    except ValueError as exc:
        st.warning(str(exc))
        st.stop()
    except psycopg.errors.QueryCanceled:
        st.error("The warehouse query exceeded 1.5 seconds. Narrow the pickup range or dimensions and retry.")
        st.stop()
    except Exception:
        reference = str(uuid.uuid4())
        LOGGER.exception("Dashboard database error", extra={"correlation_id": reference})
        st.error(f"Dashboard data is unavailable. Retry shortly or contact the operator with reference {reference}.")
        st.stop()

    _publication_messages(data.publications)
    active_dimensions = sum(
        bool(value)
        for value in (filters.boroughs, filters.zone_keys, filters.payment_keys, filters.vendor_keys, filters.rate_keys)
    )
    st.caption(
        f"Selected: {filters.start_date:%b %d, %Y} to {filters.end_date:%b %d, %Y} · "
        f"Comparison: {comparison.start_date:%b %d, %Y} to {comparison.end_date:%b %d, %Y} · "
        f"{active_dimensions} dimension filters"
    )
    if data.kpis.is_empty() or int(data.kpis.row(0, named=True).get("trip_count") or 0) == 0:
        st.info("No published taxi data match these filters. Broaden the pickup range or clear dimensions.")

    overview, demand, revenue, quality, explore = st.tabs(["Overview", "Demand", "Revenue", "Quality", "Trips"])
    with overview:
        render_overview(data)
    with demand:
        render_demand(data, Path(os.environ.get("TAXI_ZONE_GEOJSON", "dashboard/data/taxi_zones.geojson")))
    with revenue:
        render_revenue(data)
    with quality:
        render_quality(data)
    with explore:
        try:
            render_explore(filters, options, version)
        except ValueError as exc:
            st.warning(str(exc))
        except psycopg.errors.QueryCanceled:
            st.error("Trip page timed out after 1.5 seconds. Narrow the pickup range or explorer filters.")
        except Exception:
            reference = str(uuid.uuid4())
            LOGGER.exception("Explorer database error", extra={"correlation_id": reference})
            st.error(f"Trip explorer is unavailable. Operator reference: {reference}.")


def _sidebar(options: FilterOptions) -> tuple[DashboardFilters, DashboardFilters]:
    st.sidebar.header("Filters")
    latest_start = options.maximum_date.replace(day=1)
    default_start = max(latest_start, options.minimum_date)
    selected_range = st.sidebar.date_input(
        "Pickup date range",
        value=(default_start, options.maximum_date),
        min_value=options.minimum_date,
        max_value=options.maximum_date,
        help="Bounded to 366 days for predictable warehouse latency.",
    )
    start, end = _date_range(selected_range, default_start, options.maximum_date)
    prior_start, prior_end = prior_month_range(start, end)
    with st.sidebar.expander("Prior comparison"):
        comparison_range = st.date_input("Comparison pickup range", value=(prior_start, prior_end))
    compare_start, compare_end = _date_range(comparison_range, prior_start, prior_end)

    boroughs = tuple(st.sidebar.multiselect("Pickup borough", options.boroughs))
    zones = _option_multiselect("Pickup zone", options.zones)
    payments = _option_multiselect("Payment type", options.payments)
    vendors = _option_multiselect("Vendor", options.vendors)
    rates = _option_multiselect("Rate code", options.rates)
    include_outliers = st.sidebar.toggle(
        "Include statistical outliers in financial/unit metrics",
        value=False,
        help="Demand counts always include every hard-valid trip.",
    )
    return (
        DashboardFilters(start, end, boroughs, zones, payments, vendors, rates, include_outliers),
        DashboardFilters(compare_start, compare_end, boroughs, zones, payments, vendors, rates, include_outliers),
    )


@st.cache_data(ttl=300, show_spinner=False)
def _cached_filter_options(warehouse_version_key: str) -> FilterOptions:
    return queries.load_filter_options(warehouse_version_key)


@st.cache_data(ttl=300, show_spinner=False)
def _cached_dashboard_data(
    filters: DashboardFilters,
    comparison: DashboardFilters,
    warehouse_version_key: str,
) -> queries.DashboardData:
    return queries.load_dashboard_data(filters, comparison, warehouse_version_key)


def _option_multiselect(label: str, options: tuple[Option, ...]) -> tuple[int, ...]:
    keyed = {option.key: option.label for option in options}
    return tuple(
        st.sidebar.multiselect(
            label,
            options=tuple(keyed),
            format_func=lambda key: keyed[key],
        )
    )


def _date_range(value: object, fallback_start: date, fallback_end: date) -> tuple[date, date]:
    if isinstance(value, tuple) and len(value) == 2 and all(isinstance(item, date) for item in value):
        return value[0], value[1]
    if isinstance(value, list) and len(value) == 2 and all(isinstance(item, date) for item in value):
        return value[0], value[1]
    return fallback_start, fallback_end


def _publication_messages(publications: pl.DataFrame) -> None:
    if publications.is_empty():
        st.warning("Publication metadata is missing; freshness and source provenance cannot be verified.")
        return
    latest = publications.row(0, named=True)
    if any(bool(value) for value in publications["is_synthetic"].to_list()):
        st.warning(
            "Synthetic source data is visible in this selection. Do not present these values as official TLC results."
        )
    stale_hours = int(os.environ.get("DASHBOARD_STALE_HOURS", "36"))
    if is_stale(latest.get("published_at"), stale_hours=stale_hours):
        st.warning(f"Warehouse publication is stale (older than {stale_hours} hours). Check the monthly ETL status.")
    status = str(latest.get("status", "unknown"))
    if status != "success":
        st.error(f"Latest publication state is {status}; displayed data may be partial.")


def _theme() -> None:
    st.markdown(
        """
        <style>
        :root { --taxi-yellow: #f5c518; --charcoal: #252525; --paper: #fffdf6; }
        .stApp { background: var(--paper); color: var(--charcoal); }
        h1, h2, h3 { letter-spacing: -0.025em; }
        h1 { border-top: 8px solid var(--taxi-yellow); padding-top: .45rem; }
        [data-testid="stMetric"] {
          border: 1px solid #ded8ca; border-left: 5px solid var(--taxi-yellow);
          border-radius: 4px; padding: .65rem .8rem; background: white;
          box-shadow: 0 1px 2px rgba(37, 37, 37, .06);
        }
        [data-testid="stSidebar"] { background: #f4f1e8; }
        [data-testid="stToolbar"] { display: none; }
        @media (max-width: 600px) {
          [data-testid="stHorizontalBlock"] { flex-wrap: wrap; }
          [data-testid="column"] { min-width: 100% !important; }
          h1 { font-size: 1.9rem; }
        }
        </style>
        """,
        unsafe_allow_html=True,
    )


if __name__ == "__main__":
    main()
