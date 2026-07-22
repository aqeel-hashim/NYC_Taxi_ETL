from __future__ import annotations

import os
import time
from datetime import date
from statistics import quantiles

import pytest

from dashboard.queries import load_dashboard_data, load_explorer_page
from dashboard.state import DashboardFilters, ExplorerFilters

DATABASE_URL = os.environ.get("TEST_DATABASE_URL")


@pytest.mark.skipif(not DATABASE_URL, reason="TEST_DATABASE_URL is required for dashboard performance evidence")
def test_uncached_aggregate_and_explorer_p95_under_two_seconds() -> None:
    current = DashboardFilters(date(2023, 2, 1), date(2023, 2, 28))
    comparison = DashboardFilters(date(2023, 1, 1), date(2023, 1, 31))
    aggregate_times: list[float] = []
    explorer_times: list[float] = []

    for request_number in range(20):
        started = time.perf_counter()
        load_dashboard_data(current, comparison, str(request_number), DATABASE_URL)
        aggregate_times.append(time.perf_counter() - started)

        started = time.perf_counter()
        load_explorer_page(current, ExplorerFilters(), database_url=DATABASE_URL)
        explorer_times.append(time.perf_counter() - started)

    assert _p95(aggregate_times) < 2.0
    assert _p95(explorer_times) < 2.0


def _p95(values: list[float]) -> float:
    return quantiles(values, n=100, method="inclusive")[94]
