from __future__ import annotations

import logging
import uuid

import streamlit as st

from dashboard.queries import decimal_to_float, load_dashboard_data

LOGGER = logging.getLogger(__name__)

st.set_page_config(page_title="NYC Taxi Analytics", layout="wide")
st.title("NYC Taxi Analytics")
st.caption("Required Assignment 1 metrics from published warehouse facts.")

month = st.sidebar.selectbox("Month", ["2023-01", "2023-02"], index=0)

try:
    data = load_dashboard_data(month)
except Exception:
    correlation_id = str(uuid.uuid4())
    LOGGER.exception("Dashboard database error", extra={"correlation_id": correlation_id})
    st.error(f"Dashboard data is unavailable. Reference: {correlation_id}")
    st.stop()

if data.average_fare.is_empty() and data.peak_hours.is_empty() and data.revenue.is_empty():
    st.info("No published taxi data for the selected month.")
    st.stop()

col1, col2, col3 = st.columns(3)

avg_value = 0.0
if not data.average_fare.is_empty():
    avg_value = decimal_to_float(data.average_fare["avg_fare_per_mile_dollars"].mean())
col1.metric("Average Fare Per Mile", f"${avg_value:,.2f}")

if data.peak_hours.is_empty():
    col2.metric("Peak Ride Hour", "No data")
else:
    peak = data.peak_hours.row(0, named=True)
    col2.metric("Peak Ride Hour", str(peak["hour_label"]), f"{peak['trip_count']:,} trips")

revenue_total = 0.0
if not data.revenue.is_empty():
    revenue_total = sum(decimal_to_float(value) for value in data.revenue["total_revenue_dollars"].to_list())
col3.metric("Revenue", f"${revenue_total:,.2f}")

st.subheader("Average Fare Per Mile")
st.dataframe(data.average_fare, use_container_width=True, hide_index=True)

st.subheader("Peak Ride Hours")
st.dataframe(data.peak_hours, use_container_width=True, hide_index=True)

st.subheader("Revenue By Payment Type")
st.dataframe(data.revenue, use_container_width=True, hide_index=True)
