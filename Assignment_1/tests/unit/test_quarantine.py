from pathlib import Path
from unittest.mock import patch

import polars as pl
import pytest

from nyc_taxi_etl.storage.quarantine import quarantine_rejected


def test_empty_quarantine_replaces_stale_rejects(tmp_path: Path) -> None:
    rejected = pl.DataFrame({"source_row": [1]})
    path = quarantine_rejected(rejected, "2023-01", str(tmp_path))
    quarantine_rejected(rejected.clear(), "2023-01", str(tmp_path))

    assert pl.read_parquet(path).is_empty()
    assert not Path(path).with_suffix(".parquet.part").exists()


def test_quarantine_write_failure_preserves_previous_file(tmp_path: Path) -> None:
    rejected = pl.DataFrame({"source_row": [1]})
    path = quarantine_rejected(rejected, "2023-01", str(tmp_path))

    with patch.object(pl.DataFrame, "write_parquet", side_effect=OSError("disk full")), pytest.raises(OSError):
        quarantine_rejected(rejected.clear(), "2023-01", str(tmp_path))

    assert pl.read_parquet(path).to_dicts() == [{"source_row": 1}]
