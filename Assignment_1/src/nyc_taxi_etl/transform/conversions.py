"""Converter functions: float dollars → integer cents, float miles → integer millimiles, etc."""

from math import isnan


def dollars_to_cents(value: float) -> int | None:
    if value is None or isnan(value):
        return None
    return round(value * 100.0)


def miles_to_millimiles(value: float) -> int | None:
    if value is None or isnan(value):
        return None
    return round(value * 1000.0)


def seconds_between(start_ts: float | None, end_ts: float | None) -> int | None:
    if start_ts is None or end_ts is None:
        return None
    return round(end_ts - start_ts)
