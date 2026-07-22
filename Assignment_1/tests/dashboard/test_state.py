from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import pytest

from dashboard.state import DashboardFilters, ExplorerFilters, is_stale, percent_delta, prior_month_range


def test_prior_comparison_preserves_selected_day_count() -> None:
    assert prior_month_range(date(2023, 2, 1), date(2023, 2, 28)) == (date(2023, 1, 1), date(2023, 1, 31))
    assert prior_month_range(date(2023, 2, 10), date(2023, 2, 12)) == (date(2023, 2, 7), date(2023, 2, 9))


def test_delta_returns_na_for_absent_or_zero_comparison() -> None:
    assert percent_delta(120, 100) == 20
    assert percent_delta(120, 0) is None
    assert percent_delta(120, None) is None


def test_filter_ranges_are_bounded_and_ordered() -> None:
    with pytest.raises(ValueError, match="must not precede"):
        DashboardFilters(date(2023, 2, 2), date(2023, 2, 1))
    with pytest.raises(ValueError, match="366 days"):
        DashboardFilters(date(2022, 1, 1), date(2023, 2, 1))
    with pytest.raises(ValueError, match="maximum distance"):
        ExplorerFilters(minimum_distance_miles=5, maximum_distance_miles=4)


def test_stale_state_is_non_color_semantic() -> None:
    now = datetime(2026, 7, 21, tzinfo=UTC)
    assert is_stale(now - timedelta(hours=37), now=now)
    assert not is_stale(now - timedelta(hours=35), now=now)
    assert is_stale(None, now=now)
