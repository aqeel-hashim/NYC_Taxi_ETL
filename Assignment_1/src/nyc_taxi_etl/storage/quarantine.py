from __future__ import annotations

from pathlib import Path

import polars as pl


def quarantine_rejected(rejected: pl.DataFrame, source_month: str, base_dir: str = "data/quarantine") -> str:
    path = Path(base_dir, source_month, "rejected.parquet")
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(".parquet.part")
    try:
        rejected.write_parquet(partial)
        partial.replace(path)
    finally:
        partial.unlink(missing_ok=True)
    return str(path)
