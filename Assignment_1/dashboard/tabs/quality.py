from __future__ import annotations

import importlib
import os

import streamlit as st

from dashboard.queries import DashboardData
from dashboard.tabs.common import COLORS, PLOTLY_CONFIG

go = importlib.import_module("plotly.graph_objects")


def render(data: DashboardData) -> None:
    st.subheader("Data quality")
    if data.publications.is_empty():
        st.warning("No publication state is available for this range.")
    else:
        latest = data.publications.row(0, named=True)
        raw = int(latest.get("source_rows") or 0)
        accepted = int(latest.get("accepted_rows") or 0)
        rejected = int(latest.get("rejected_rows") or 0)
        loaded = int(latest.get("loaded_rows") or 0)
        published = int(latest.get("published_rows") or 0)
        flagged = int(latest.get("flagged_rows") or 0)
        if raw != accepted + rejected:
            st.error("Reconciliation failed: raw must equal accepted plus rejected.")
        reconciliation = go.Figure(
            go.Bar(
                x=["Raw", "Accepted", "Rejected", "Loaded", "Published"],
                y=[raw, accepted, rejected, loaded, published],
                marker_color=[COLORS[1], COLORS[2], COLORS[3], COLORS[2], COLORS[2]],
                text=[raw, accepted, rejected, loaded, published],
            )
        )
        reconciliation.update_layout(title="Reconciliation: raw = accepted + rejected; loaded = published = accepted")
        st.plotly_chart(reconciliation, width="stretch", config=PLOTLY_CONFIG)
        rejected_rate = 100.0 * rejected / raw if raw else 0.0
        flagged_rate = 100.0 * flagged / accepted if accepted else 0.0
        rejected_column, flagged_column = st.columns(2)
        rejected_column.metric("Rejected rows", f"{rejected:,}", f"{rejected_rate:.1f}% of source")
        flagged_column.metric(
            "Flagged accepted rows",
            f"{flagged:,}",
            f"{flagged_rate:.1f}% of accepted",
            help="Flagged rows remain an accepted subset, not a loss stage.",
        )
        st.dataframe(data.publications, hide_index=True, width="stretch")

    st.markdown("#### Accepted-row flag reasons")
    if data.quality.is_empty():
        st.info("No quality issues were recorded for this range.")
    else:
        st.dataframe(data.quality, hide_index=True, width="stretch")

    st.markdown("#### KLL and reference versions")
    if data.thresholds.is_empty():
        st.info("Threshold version metadata is unavailable for this selection.")
    else:
        st.dataframe(data.thresholds, hide_index=True, width="stretch")
    st.markdown("#### Source and schema fingerprints")
    if data.fingerprints.is_empty():
        st.info("Source fingerprint metadata is unavailable for this selection.")
    else:
        st.dataframe(data.fingerprints, hide_index=True, width="stretch")
    st.markdown("#### Recorded failed runs")
    if data.alerts.is_empty():
        st.info("No failed runs are recorded in the warehouse.")
    else:
        st.dataframe(data.alerts, hide_index=True, width="stretch")
    links = [
        f"[{label}]({url})"
        for label, url in (
            ("Airflow", os.environ.get("AIRFLOW_URL")),
            ("Grafana", os.environ.get("GRAFANA_URL")),
            ("Loki", os.environ.get("LOKI_URL")),
        )
        if url
    ]
    if links:
        st.markdown("Operator links: " + " | ".join(links))
