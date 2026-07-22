from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal


@dataclass(frozen=True)
class Option:
    key: int
    label: str


@dataclass(frozen=True)
class FilterOptions:
    minimum_date: date
    maximum_date: date
    boroughs: tuple[str, ...]
    zones: tuple[Option, ...]
    payments: tuple[Option, ...]
    vendors: tuple[Option, ...]
    rates: tuple[Option, ...]


@dataclass(frozen=True)
class DashboardFilters:
    start_date: date
    end_date: date
    boroughs: tuple[str, ...] = ()
    zone_keys: tuple[int, ...] = ()
    payment_keys: tuple[int, ...] = ()
    vendor_keys: tuple[int, ...] = ()
    rate_keys: tuple[int, ...] = ()
    include_outliers: bool = False

    def __post_init__(self) -> None:
        if self.end_date < self.start_date:
            raise ValueError("pickup end date must not precede start date")
        if self.end_date - self.start_date > timedelta(days=366):
            raise ValueError("pickup date range must be 366 days or fewer")


@dataclass(frozen=True)
class ExplorerFilters:
    dropoff_zone_keys: tuple[int, ...] = ()
    quality_only: bool = False
    minimum_distance_miles: float | None = None
    maximum_distance_miles: float | None = None
    minimum_duration_minutes: float | None = None
    maximum_duration_minutes: float | None = None
    minimum_total_dollars: float | None = None
    maximum_total_dollars: float | None = None

    def __post_init__(self) -> None:
        for low, high, label in (
            (self.minimum_distance_miles, self.maximum_distance_miles, "distance"),
            (self.minimum_duration_minutes, self.maximum_duration_minutes, "duration"),
            (self.minimum_total_dollars, self.maximum_total_dollars, "total amount"),
        ):
            if low is not None and high is not None and high < low:
                raise ValueError(f"maximum {label} must not be below minimum")


@dataclass(frozen=True)
class Cursor:
    pickup_at_local: datetime
    trip_key: int


def prior_month_range(start: date, end: date) -> tuple[date, date]:
    next_month = date(start.year + (start.month == 12), 1 if start.month == 12 else start.month + 1, 1)
    if start.day == 1 and end == next_month - timedelta(days=1):
        prior_end = start - timedelta(days=1)
        return prior_end.replace(day=1), prior_end
    days = (end - start).days
    prior_end = start - timedelta(days=1)
    return prior_end - timedelta(days=days), prior_end


def percent_delta(current: object, prior: object) -> float | None:
    current_number = _number(current)
    prior_number = _number(prior)
    if current_number is None or prior_number in (None, 0.0):
        return None
    return 100.0 * (current_number - prior_number) / prior_number


def is_stale(published_at: object, stale_hours: int = 36, now: datetime | None = None) -> bool:
    if not isinstance(published_at, datetime):
        return True
    timestamp = published_at if published_at.tzinfo else published_at.replace(tzinfo=UTC)
    return (now or datetime.now(UTC)) - timestamp > timedelta(hours=stale_hours)


def _number(value: object) -> float | None:
    if isinstance(value, Decimal | int | float):
        return float(value)
    return None
