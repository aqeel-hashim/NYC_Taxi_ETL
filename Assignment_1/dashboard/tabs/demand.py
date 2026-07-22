from __future__ import annotations

import importlib
from pathlib import Path

import polars as pl
import streamlit as st

from dashboard.geometry import TLC_ATTRIBUTION, load_geojson, quantile_classes
from dashboard.queries import DashboardData, decimal_to_float
from dashboard.tabs.common import COLORS, PLOTLY_CONFIG, movers

px = importlib.import_module("plotly.express")


def render(data: DashboardData, geometry_path: Path) -> None:
    st.subheader("Demand")
    if data.hourly.is_empty():
        st.info("No demand data matches these filters.")
        return

    peak = data.hourly.sort("trip_count", descending=True).row(0, named=True)
    st.metric("Peak ride hour", f"{int(peak['pickup_hour']):02d}:00")
    st.caption(f"{int(peak['trip_count']):,} trips in the selected period")

    daily = px.line(
        data.daily, x="pickup_date", y="trip_count", title="Daily trips", color_discrete_sequence=[COLORS[1]]
    )
    st.plotly_chart(daily, width="stretch", config=PLOTLY_CONFIG)

    heatmap = px.density_heatmap(
        data.heatmap,
        x="pickup_hour",
        y="weekday_name",
        z="trip_count",
        category_orders={
            "weekday_name": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        },
        color_continuous_scale=["#FFF8D6", COLORS[0], "#6F5600"],
        title="Weekday by pickup hour",
    )
    heatmap.update_xaxes(tickvals=list(range(0, 24, 3)), ticktext=[f"{hour:02d}:00" for hour in range(0, 24, 3)])
    st.plotly_chart(heatmap, width="stretch", config=PLOTLY_CONFIG)

    st.markdown("#### Pickup zones")
    map_metric = st.selectbox(
        "Map metric",
        options=("trip_count", "gross_revenue_dollars", "revenue_per_trip_dollars", "fare_per_mile_dollars"),
        format_func=lambda value: value.replace("_", " ").title(),
    )
    geometry = load_geojson(geometry_path)
    if geometry is None:
        st.warning("Taxi-zone map unavailable. Build dashboard/data/taxi_zones.geojson with dashboard/geometry.py.")
    elif not data.zones.is_empty():
        values = [decimal_to_float(value) for value in data.zones[map_metric]]
        mapped = data.zones.with_columns(pl.Series("quantile_class", quantile_classes(values)))
        figure = px.choropleth(
            mapped,
            geojson=geometry,
            locations="pickup_zone_key",
            featureidkey="properties.LocationID",
            color="quantile_class",
            hover_name="pickup_zone_label",
            hover_data={map_metric: True, "quantile_class": False},
            color_continuous_scale=["#FFF8D6", COLORS[0], "#6F5600"],
            range_color=(0, 4),
            title=f"{map_metric.replace('_', ' ').title()} by quantile",
        )
        figure.update_geos(fitbounds="locations", visible=False)
        figure.update_coloraxes(
            colorbar={
                "title": "Demand quintile",
                "tickvals": [0, 1, 2, 3, 4],
                "ticktext": ["Q1", "Q2", "Q3", "Q4", "Q5"],
            }
        )
        figure.update_layout(margin={"l": 0, "r": 0, "t": 50, "b": 0})
        st.plotly_chart(figure, width="stretch", config=PLOTLY_CONFIG)
        st.caption(TLC_ATTRIBUTION)

    st.dataframe(data.zones.head(20), hide_index=True, width="stretch")
    speed = px.line(
        data.hourly,
        x="pickup_hour",
        y="weighted_network_speed_mph",
        title="Weighted network speed by hour",
        color_discrete_sequence=[COLORS[2]],
    )
    st.plotly_chart(speed, width="stretch", config=PLOTLY_CONFIG)

    zone_movers = movers(data.zones, data.comparison_zones, "pickup_zone_key", "pickup_zone_label", "trip_count")
    st.markdown("#### Top pickup-zone movers vs prior period")
    if zone_movers.is_empty():
        st.info("Prior-period zone comparison is unavailable.")
    else:
        st.dataframe(zone_movers, hide_index=True, width="stretch")
