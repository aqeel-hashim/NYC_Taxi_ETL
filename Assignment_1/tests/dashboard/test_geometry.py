from __future__ import annotations

import json
from pathlib import Path

import pytest

from dashboard.geometry import load_geojson, quantile_classes


def test_quantile_classes_preserve_range_and_order() -> None:
    classes = quantile_classes([1, 2, 3, 100, 1000])
    assert classes == sorted(classes)
    assert min(classes) == 0
    assert max(classes) == 4


def test_geojson_loader_rejects_wrong_payload(tmp_path: Path) -> None:
    path = tmp_path / "zones.geojson"
    path.write_text(json.dumps({"type": "Point"}))
    with pytest.raises(ValueError, match="FeatureCollection"):
        load_geojson(path)


def test_missing_geojson_is_an_explicit_state(tmp_path: Path) -> None:
    assert load_geojson(tmp_path / "missing.geojson") is None
