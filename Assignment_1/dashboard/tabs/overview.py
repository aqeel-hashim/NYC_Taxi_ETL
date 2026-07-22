from __future__ import annotations

import importlib

import streamlit as st

from dashboard.queries import DashboardData, decimal_to_float
from dashboard.tabs.common import COLORS, PLOTLY_CONFIG, delta_text, scalar

go = importlib.import_module("plotly.graph_objects")
make_subplots = importlib.import_module("plotly.subplots").make_subplots


def render(data: DashboardData) -> None:
    st.subheader("Executive overview")
    current = data.kpis
    previous = data.comparison_kpis
    metrics = (
        ("Trips", "trip_count", ",.0f", ""),
        ("Gross revenue", "gross_revenue_dollars", ",.2f", "$"),
        ("Revenue / trip", "revenue_per_trip_dollars", ",.2f", "$"),
        ("Fare / mile", "fare_per_mile_dollars", ",.2f", "$"),
        ("Average duration", "average_duration_minutes", ",.1f", " min"),
        ("Recorded card tip rate", "recorded_card_tip_rate", ",.1f", "%"),
    )
    for row_start in (0, 3):
        columns = st.columns(3)
        for column, (label, field, number_format, unit) in zip(
            columns, metrics[row_start : row_start + 3], strict=True
        ):
            value = scalar(current, field)
            prior = scalar(previous, field)
            prefix = "$" if unit == "$" else ""
            suffix = "" if unit == "$" else unit
            rendered = "N/A" if value is None else f"{prefix}{decimal_to_float(value):{number_format}}{suffix}"
            column.metric(label, rendered, delta_text(value, prior))

    if data.daily.is_empty():
        st.info("No published trips match these filters. Broaden the pickup range or dimensions.")
        return

    figure = make_subplots(specs=[[{"secondary_y": True}]])
    figure.add_trace(
        go.Scatter(x=data.daily["pickup_date"], y=data.daily["trip_count"], name="Trips", line={"color": COLORS[1]}),
        secondary_y=False,
    )
    figure.add_trace(
        go.Scatter(
            x=data.daily["pickup_date"],
            y=[decimal_to_float(value) for value in data.daily["gross_revenue_dollars"]],
            name="Gross revenue",
            line={"color": COLORS[0], "dash": "dot"},
        ),
        secondary_y=True,
    )
    figure.update_layout(title="Daily demand and revenue", margin={"l": 10, "r": 10, "t": 50, "b": 10})
    figure.update_yaxes(title_text="Trips", secondary_y=False)
    figure.update_yaxes(title_text="Gross revenue ($)", secondary_y=True)
    st.plotly_chart(figure, width="stretch", config=PLOTLY_CONFIG)

    st.markdown("#### Publication state")
    if data.publications.is_empty():
        st.warning("Publication metadata is absent. Verify the monthly publish completed.")
    else:
        st.dataframe(data.publications, hide_index=True, width="stretch")
