from __future__ import annotations

import streamlit as st

from dashboard import queries
from dashboard.state import Cursor, DashboardFilters, ExplorerFilters, FilterOptions


def render(filters: DashboardFilters, options: FilterOptions, warehouse_version: str) -> None:
    st.subheader("Explore trips")
    st.caption("Read-only keyset pagination; 100 rows per page; pickup timestamp and trip key ordering only.")

    with st.expander("Explorer filters"):
        dropoff_labels = {option.key: option.label for option in options.zones}
        dropoffs = st.multiselect(
            "Dropoff zones",
            options=tuple(dropoff_labels),
            format_func=lambda key: dropoff_labels[key],
        )
        quality_only = st.checkbox("Quality-flagged trips only")
        c1, c2, c3 = st.columns(3)
        minimum_distance = c1.number_input("Minimum distance (miles)", min_value=0.0, value=0.0)
        maximum_distance = c1.number_input("Maximum distance (miles; 0 = any)", min_value=0.0, value=0.0)
        minimum_duration = c2.number_input("Minimum duration (minutes)", min_value=0.0, value=0.0)
        maximum_duration = c2.number_input("Maximum duration (minutes; 0 = any)", min_value=0.0, value=0.0)
        minimum_total = c3.number_input("Minimum total ($)", min_value=0.0, value=0.0)
        maximum_total = c3.number_input("Maximum total ($; 0 = any)", min_value=0.0, value=0.0)

    explorer = ExplorerFilters(
        dropoff_zone_keys=tuple(dropoffs),
        quality_only=quality_only,
        minimum_distance_miles=minimum_distance or None,
        maximum_distance_miles=maximum_distance or None,
        minimum_duration_minutes=minimum_duration or None,
        maximum_duration_minutes=maximum_duration or None,
        minimum_total_dollars=minimum_total or None,
        maximum_total_dollars=maximum_total or None,
    )
    state_key = (filters, explorer, warehouse_version)
    if st.session_state.get("explorer_state_key") != state_key:
        st.session_state.explorer_state_key = state_key
        st.session_state.explorer_page = queries.load_explorer_page(filters, explorer)
        st.session_state.explorer_page_number = 1

    page: queries.ExplorerPage = st.session_state.explorer_page
    first = _cursor(page, first=True)
    last = _cursor(page, first=False)
    previous, page_label, following = st.columns([1, 2, 1])
    previous_clicked = previous.button(
        "Previous 100", disabled=first is None or st.session_state.explorer_page_number == 1
    )
    following_clicked = following.button("Next 100", disabled=last is None or not page.has_more)

    if previous_clicked and first is not None:
        previous_page = queries.load_explorer_page(filters, explorer, first, "previous")
        st.session_state.explorer_page = queries.ExplorerPage(rows=previous_page.rows, has_more=True)
        st.session_state.explorer_page_number -= 1
        st.rerun()
    elif following_clicked and last is not None:
        st.session_state.explorer_page = queries.load_explorer_page(filters, explorer, last, "next")
        st.session_state.explorer_page_number += 1
        st.rerun()

    page_label.markdown(
        f"<p style='text-align:center'>Page {st.session_state.explorer_page_number}</p>", unsafe_allow_html=True
    )
    if page.rows.is_empty():
        st.info("No trips match these bounded filters.")
        return
    st.dataframe(page.rows, hide_index=True, width="stretch")
    st.download_button(
        "Download current page CSV",
        page.rows.write_csv(),
        file_name=f"taxi-trips-page-{st.session_state.explorer_page_number}.csv",
        mime="text/csv",
    )


def _cursor(page: queries.ExplorerPage, *, first: bool) -> Cursor | None:
    if page.rows.is_empty():
        return None
    row = page.rows.row(0 if first else -1, named=True)
    return Cursor(pickup_at_local=row["pickup_at_local"], trip_key=int(row["trip_key"]))
