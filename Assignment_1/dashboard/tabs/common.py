from __future__ import annotations

from collections.abc import Iterable

import polars as pl

from dashboard.queries import decimal_to_float
from dashboard.state import percent_delta

PLOTLY_CONFIG = {"displayModeBar": False, "responsive": True}
COLORS = ["#8A6400", "#252525", "#0072B2", "#D55E00", "#009E73"]


def scalar(frame: pl.DataFrame, column: str) -> object:
    if frame.is_empty() or column not in frame.columns:
        return None
    return frame.row(0, named=True).get(column)


def delta_text(current: object, previous: object) -> str:
    change = percent_delta(current, previous)
    return "N/A" if change is None else f"{change:+.1f}% vs prior"


def as_floats(values: Iterable[object]) -> list[float]:
    return [decimal_to_float(value) for value in values]


def movers(current: pl.DataFrame, previous: pl.DataFrame, key: str, label: str, value: str) -> pl.DataFrame:
    if current.is_empty() or previous.is_empty():
        return pl.DataFrame()
    prior = {row[key]: decimal_to_float(row[value]) for row in previous.iter_rows(named=True)}
    rows = []
    for row in current.iter_rows(named=True):
        old = prior.get(row[key])
        now = decimal_to_float(row[value])
        if old in (None, 0.0):
            continue
        rows.append({label: row[label], "change_percent": 100.0 * (now - old) / old})
    return pl.DataFrame(rows).sort("change_percent", descending=True).head(10) if rows else pl.DataFrame()
