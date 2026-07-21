from __future__ import annotations

import subprocess
from pathlib import Path

import polars as pl
import pytest

from nyc_taxi_etl import pipeline
from nyc_taxi_etl.pipeline import PipelineResult


def test_main_success(monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    def fake_run(month: str, *, database_url: str, fixture: bool = False) -> PipelineResult:
        assert (month, database_url, fixture) == ("2023-01", "db", True)
        return PipelineResult(6, 4, 2, 1, 2, 4, 0, "abc")

    monkeypatch.setattr(pipeline, "run_pipeline", fake_run)
    assert pipeline.main(["2023-01", "--fixture", "--database-url", "db"]) == pipeline.SUCCESS
    output = capsys.readouterr().out
    assert "source=6 accepted=4 rejected=2 flagged_rows=1 issue_rows=2 duplicates=0 sha256=abc" in output


def test_main_uses_database_url_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_run(month: str, *, database_url: str, fixture: bool = False) -> PipelineResult:
        assert database_url == "env-db"
        return PipelineResult(1, 1, 0, 0, 0, 1, 0, "abc")

    monkeypatch.setenv("DATABASE_URL", "env-db")
    monkeypatch.setattr(pipeline, "run_pipeline", fake_run)
    assert pipeline.main(["2023-01"]) == pipeline.SUCCESS


def test_main_error_codes(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    assert pipeline.main(["2023-01"]) == pipeline.DATABASE_ERROR

    def value_error(_month: str, *, database_url: str, fixture: bool = False) -> PipelineResult:
        raise ValueError("bad month")

    monkeypatch.setattr(pipeline, "run_pipeline", value_error)
    assert pipeline.main(["2023-99", "--database-url", "db"]) == pipeline.USAGE_ERROR

    def source_error(_month: str, *, database_url: str, fixture: bool = False) -> PipelineResult:
        raise RuntimeError("bad source")

    monkeypatch.setattr(pipeline, "run_pipeline", source_error)
    assert pipeline.main(["2023-01", "--database-url", "db"]) == pipeline.SOURCE_ERROR

    def database_error(_month: str, *, database_url: str, fixture: bool = False) -> PipelineResult:
        raise TypeError("bad db")

    monkeypatch.setattr(pipeline, "run_pipeline", database_error)
    assert pipeline.main(["2023-01", "--database-url", "db"]) == pipeline.DATABASE_ERROR


def test_resolve_source_downloads_when_missing(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[list[str]] = []

    def fake_run(args: list[str], *, check: bool) -> subprocess.CompletedProcess[str]:
        calls.append(args)
        Path(args[-1]).write_text("x")
        return subprocess.CompletedProcess(args, 0)

    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr("nyc_taxi_etl.pipeline.subprocess.run", fake_run)
    path, url = pipeline._resolve_source("2023-01", fixture=False)
    assert path == Path("data/yellow_tripdata_2023-01.parquet")
    assert url.endswith("yellow_tripdata_2023-01.parquet")
    assert calls == [["curl", "-fL", url, "-o", str(path)]]


def test_pipeline_normalizes_airport_fee_column(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    pl.DataFrame({"Airport_fee": [1.0]}).write_parquet(tmp_path / "source.parquet")

    monkeypatch.setattr(pipeline, "_resolve_source", lambda _month, fixture: (tmp_path / "source.parquet", "fixture"))
    monkeypatch.setattr(pipeline, "validate_contract", lambda frame: type("Contract", (), {"is_valid": True})())

    def fake_transform(frame: pl.DataFrame, _month: str) -> None:
        assert "airport_fee" in frame.columns
        raise RuntimeError("stop")

    monkeypatch.setattr(pipeline, "transform", fake_transform)
    with pytest.raises(RuntimeError, match="stop"):
        pipeline.run_pipeline("2023-02", database_url="postgresql://unused", fixture=True)
