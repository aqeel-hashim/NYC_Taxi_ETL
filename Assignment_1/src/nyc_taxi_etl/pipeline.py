from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import polars as pl

from nyc_taxi_etl.contracts.source import validate_contract
from nyc_taxi_etl.load.warehouse import load_month
from nyc_taxi_etl.transform.trips import transform

SUCCESS = 0
USAGE_ERROR = 2
SOURCE_ERROR = 3
DATABASE_ERROR = 4
MONTH_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
SOURCE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{month}.parquet"


@dataclass(frozen=True)
class PipelineResult:
    source_rows: int
    accepted_rows: int
    rejected_rows: int
    flagged_rows: int
    issue_rows: int
    inserted_rows: int
    duplicate_source_rows: int
    sha256: str


def run_pipeline(month: str, *, database_url: str, fixture: bool = False) -> PipelineResult:
    if not MONTH_RE.fullmatch(month):
        raise ValueError("month must be YYYY-MM")
    source_path, source_url = _resolve_source(month, fixture=fixture)
    raw = pl.read_parquet(source_path)
    contract = validate_contract(raw)
    if not contract.is_valid:
        raise RuntimeError(f"source contract failed: {contract.status.name}")
    source_hash = _sha256(source_path)
    result = transform(raw, month)
    if result.source_rows != result.accepted_rows + result.rejected_rows:
        raise RuntimeError("source row reconciliation failed")
    load_result = load_month(
        database_url,
        result,
        source_asset_id=f"yellow_tripdata_{month}:{source_hash[:12]}",
        source_version=source_hash,
        source_url=source_url,
        sha256=source_hash,
        byte_size=source_path.stat().st_size,
    )
    return PipelineResult(
        source_rows=result.source_rows,
        accepted_rows=result.accepted_rows,
        rejected_rows=result.rejected_rows,
        flagged_rows=result.flagged_rows,
        issue_rows=len(result.issues),
        inserted_rows=load_result.inserted_rows,
        duplicate_source_rows=load_result.duplicate_source_rows,
        sha256=source_hash,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Load one NYC Yellow Taxi month")
    parser.add_argument("month")
    parser.add_argument("--fixture", action="store_true")
    parser.add_argument("--database-url", default=None)
    args = parser.parse_args(argv)
    database_url = args.database_url
    if not database_url:
        import os

        database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        print("DATABASE_URL is required", file=sys.stderr)
        return DATABASE_ERROR
    try:
        result = run_pipeline(args.month, database_url=database_url, fixture=args.fixture)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return USAGE_ERROR
    except (pl.exceptions.PolarsError, RuntimeError, subprocess.CalledProcessError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return SOURCE_ERROR
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return DATABASE_ERROR
    print(
        " ".join(
            (
                f"source={result.source_rows}",
                f"accepted={result.accepted_rows}",
                f"rejected={result.rejected_rows}",
                f"flagged_rows={result.flagged_rows}",
                f"issue_rows={result.issue_rows}",
                f"duplicates={result.duplicate_source_rows}",
                f"sha256={result.sha256}",
            )
        )
    )
    return SUCCESS


def _resolve_source(month: str, *, fixture: bool) -> tuple[Path, str]:
    if fixture:
        from nyc_taxi_etl.fixtures import write_taxi_fixture

        return write_taxi_fixture(Path("tests/fixtures/yellow_tripdata_fixture.parquet")), "fixture"
    data_dir = Path("data")
    data_dir.mkdir(exist_ok=True)
    path = data_dir / f"yellow_tripdata_{month}.parquet"
    url = SOURCE_URL.format(month=month)
    if not path.exists():
        subprocess.run(["curl", "-fL", url, "-o", str(path)], check=True)
    return path, url


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
