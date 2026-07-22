from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from dashboard.queries import DashboardData
    from dashboard.state import DashboardFilters, FilterOptions


def render_overview(data: DashboardData) -> None:
    from dashboard.tabs.overview import render

    render(data)


def render_demand(data: DashboardData, geometry_path: Path) -> None:
    from dashboard.tabs.demand import render

    render(data, geometry_path)


def render_revenue(data: DashboardData) -> None:
    from dashboard.tabs.revenue import render

    render(data)


def render_quality(data: DashboardData) -> None:
    from dashboard.tabs.quality import render

    render(data)


def render_explore(filters: DashboardFilters, options: FilterOptions, warehouse_version: str) -> None:
    from dashboard.tabs.explore import render

    render(filters, options, warehouse_version)


__all__ = ["render_demand", "render_explore", "render_overview", "render_quality", "render_revenue"]
