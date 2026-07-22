from __future__ import annotations

from datetime import UTC, date, datetime
from unittest.mock import patch

import polars as pl
from streamlit.testing.v1 import AppTest

from dashboard.queries import DashboardData, ExplorerPage
from dashboard.state import FilterOptions, Option


def test_app_has_shared_filters_five_tabs_and_states() -> None:
    options = FilterOptions(
        date(2023, 1, 1),
        date(2023, 2, 28),
        ("Manhattan",),
        (Option(1, "Midtown"),),
        (Option(1, "Credit card"),),
        (Option(1, "Vendor"),),
        (Option(1, "Standard"),),
    )
    data = _dashboard_data()
    explorer = ExplorerPage(
        pl.DataFrame(
            {
                "pickup_at_local": [datetime(2023, 2, 1, 12)],
                "trip_key": [1],
                "dropoff_at_local": [datetime(2023, 2, 1, 12, 10)],
            }
        ),
        has_more=False,
    )
    with (
        patch("dashboard.queries.warehouse_version", return_value="7"),
        patch("dashboard.queries.load_filter_options", return_value=options),
        patch("dashboard.queries.load_dashboard_data", return_value=data),
        patch("dashboard.queries.load_explorer_page", return_value=explorer),
    ):
        app = AppTest.from_file("dashboard/app.py").run(timeout=20)

    assert not app.exception
    assert not app.error
    assert [tab.label for tab in app.tabs] == ["Overview", "Demand", "Revenue", "Quality", "Trips"]
    assert any(item.label == "Pickup borough" for item in app.multiselect)
    assert any("Synthetic source data" in warning.value for warning in app.warning)


def test_app_hides_database_errors_behind_reference() -> None:
    with patch("dashboard.queries.warehouse_version", side_effect=RuntimeError("secret database detail")):
        app = AppTest.from_file("dashboard/app.py").run(timeout=10)
    assert not app.exception
    assert len(app.error) == 1
    assert "reference" in app.error[0].value
    assert "secret database detail" not in app.error[0].value


def _dashboard_data() -> DashboardData:
    kpis = pl.DataFrame(
        {
            "trip_count": [100],
            "gross_revenue_dollars": [1000.0],
            "revenue_per_trip_dollars": [10.0],
            "fare_per_mile_dollars": [5.0],
            "average_duration_minutes": [12.0],
            "recorded_card_tip_rate": [18.0],
        }
    )
    daily = pl.DataFrame(
        {
            "pickup_date": [date(2023, 2, 1)],
            "trip_count": [100],
            "gross_revenue_dollars": [1000.0],
            "fare_per_mile_dollars": [5.0],
        }
    )
    hourly = pl.DataFrame({"pickup_hour": [12], "trip_count": [100], "weighted_network_speed_mph": [15.0]})
    heatmap = pl.DataFrame(
        {"weekday_number": [3], "weekday_name": ["Wednesday"], "pickup_hour": [12], "trip_count": [100]}
    )
    zones = pl.DataFrame(
        {
            "pickup_zone_key": [1],
            "pickup_zone_label": ["Midtown"],
            "pickup_borough": ["Manhattan"],
            "trip_count": [100],
            "gross_revenue_dollars": [1000.0],
            "revenue_per_trip_dollars": [10.0],
            "fare_per_mile_dollars": [5.0],
        }
    )
    breakdown = pl.DataFrame(
        {
            "payment_type_key": [1],
            "payment_type_label": ["Credit card"],
            "gross_revenue_dollars": [1000.0],
            "trip_count": [100],
            "revenue_per_trip_dollars": [10.0],
            "recorded_card_tip_rate": [18.0],
        }
    )
    vendor = breakdown.rename({"payment_type_key": "vendor_key", "payment_type_label": "vendor_label"})
    rate = breakdown.rename({"payment_type_key": "rate_code_key", "payment_type_label": "rate_code_label"})
    publications = pl.DataFrame(
        {
            "source_month": ["2023-02"],
            "status": ["success"],
            "published_at": [datetime.now(UTC)],
            "source_rows": [110],
            "accepted_rows": [100],
            "rejected_rows": [10],
            "flagged_rows": [2],
            "loaded_rows": [100],
            "published_rows": [100],
            "is_synthetic": [True],
            "warehouse_version": ["7"],
        }
    )
    empty = pl.DataFrame()
    return DashboardData(
        kpis=kpis,
        comparison_kpis=kpis,
        daily=daily,
        hourly=hourly,
        heatmap=heatmap,
        zones=zones,
        comparison_zones=zones,
        payments=breakdown,
        comparison_payments=breakdown,
        vendors=vendor,
        comparison_vendors=vendor,
        rates=rate,
        comparison_rates=rate,
        components=pl.DataFrame({"fare": [800.0], "tips": [200.0]}),
        publications=publications,
        quality=empty,
        fingerprints=empty,
        thresholds=empty,
        alerts=empty,
    )
