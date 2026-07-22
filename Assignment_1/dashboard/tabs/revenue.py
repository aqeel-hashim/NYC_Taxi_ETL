from __future__ import annotations

import importlib

import streamlit as st

from dashboard.queries import DashboardData, decimal_to_float
from dashboard.tabs.common import COLORS, PLOTLY_CONFIG, movers, scalar

px = importlib.import_module("plotly.express")
go = importlib.import_module("plotly.graph_objects")
make_subplots = importlib.import_module("plotly.subplots").make_subplots


def render(data: DashboardData) -> None:
    st.subheader("Revenue")
    if data.daily.is_empty():
        st.info("No financial data matches these filters.")
        return

    daily = make_subplots(specs=[[{"secondary_y": True}]])
    daily.add_trace(
        go.Scatter(
            x=data.daily["pickup_date"],
            y=data.daily["gross_revenue_dollars"],
            name="Gross revenue",
            line={"color": COLORS[0]},
        ),
        secondary_y=False,
    )
    daily.add_trace(
        go.Scatter(
            x=data.daily["pickup_date"],
            y=data.daily["fare_per_mile_dollars"],
            name="Fare per mile",
            line={"color": COLORS[2], "dash": "dot"},
        ),
        secondary_y=True,
    )
    daily.update_layout(title="Daily revenue and unit economics")
    daily.update_yaxes(title_text="Gross revenue ($)", secondary_y=False)
    daily.update_yaxes(title_text="Fare per mile ($)", secondary_y=True)
    st.plotly_chart(daily, width="stretch", config=PLOTLY_CONFIG)

    left, right = st.columns(2)
    payment = px.bar(
        data.payments,
        x="payment_type_label",
        y="gross_revenue_dollars",
        title="Revenue by payment type",
        color_discrete_sequence=[COLORS[0]],
    )
    left.plotly_chart(payment, width="stretch", config=PLOTLY_CONFIG)
    tip_rate = scalar(data.kpis, "recorded_card_tip_rate")
    right.metric("Recorded credit-card tip rate", "N/A" if tip_rate is None else f"{decimal_to_float(tip_rate):.1f}%")
    right.dataframe(data.payments, hide_index=True, width="stretch")

    if not data.components.is_empty():
        row = data.components.row(0, named=True)
        labels = list(row)
        values = [decimal_to_float(row[label]) for label in labels]
        components = go.Figure(
            go.Bar(x=[label.replace("_", " ").title() for label in labels], y=values, marker_color=COLORS[0])
        )
        components.update_layout(title="Revenue components", yaxis_title="Dollars ($)", showlegend=False)
        st.plotly_chart(components, width="stretch", config=PLOTLY_CONFIG)

    comparisons = (
        ("Vendor", data.vendors, data.comparison_vendors, "vendor_key", "vendor_label"),
        ("Rate code", data.rates, data.comparison_rates, "rate_code_key", "rate_code_label"),
        ("Payment", data.payments, data.comparison_payments, "payment_type_key", "payment_type_label"),
    )
    for title, current, previous, key, label in comparisons:
        st.markdown(f"#### {title} comparison")
        st.dataframe(current, hide_index=True, width="stretch")
        changed = movers(current, previous, key, label, "gross_revenue_dollars")
        if changed.is_empty():
            st.caption("Prior-period comparison unavailable.")
        else:
            st.dataframe(changed, hide_index=True, width="stretch")
