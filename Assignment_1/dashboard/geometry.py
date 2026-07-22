from __future__ import annotations

import argparse
import importlib
import json
from bisect import bisect_right
from collections.abc import Sequence
from pathlib import Path
from typing import Any, cast

TLC_GEOMETRY_URL = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zones.zip"
TLC_ATTRIBUTION = "NYC Taxi & Limousine Commission Taxi Zone Geometry"


def preprocess_shapefile(
    source: Path,
    destination: Path,
    *,
    source_crs: str = "EPSG:2263",
    tolerance_degrees: float = 0.00015,
) -> None:
    try:
        shapefile = importlib.import_module("shapefile")
        pyproj = importlib.import_module("pyproj")
        geometry_module = importlib.import_module("shapely.geometry")
        operations_module = importlib.import_module("shapely.ops")
    except ImportError as exc:  # pragma: no cover - exercised by the standalone build command
        raise RuntimeError("geometry build requires pyproj, pyshp, and shapely") from exc

    transformer = pyproj.Transformer.from_crs(source_crs, "EPSG:4326", always_xy=True)
    features: list[dict[str, Any]] = []
    with shapefile.Reader(str(source)) as reader:
        for item in reader.iterShapeRecords():
            properties = item.record.as_dict()
            location_id = properties.get("LocationID", properties.get("location_i"))
            if location_id is None:
                raise ValueError("taxi-zone geometry has no LocationID field")
            geometry = operations_module.transform(
                transformer.transform,
                geometry_module.shape(item.shape.__geo_interface__),
            ).simplify(
                tolerance_degrees,
                preserve_topology=True,
            )
            features.append(
                {
                    "type": "Feature",
                    "id": int(location_id),
                    "properties": {
                        "LocationID": int(location_id),
                        "zone": properties.get("zone"),
                        "borough": properties.get("borough"),
                    },
                    "geometry": geometry_module.mapping(geometry),
                }
            )

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(
            {
                "type": "FeatureCollection",
                "name": "NYC TLC Taxi Zones",
                "crs": {"type": "name", "properties": {"name": "EPSG:4326"}},
                "attribution": TLC_ATTRIBUTION,
                "features": features,
            },
            separators=(",", ":"),
        )
    )


def load_geojson(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    payload = json.loads(path.read_text())
    if payload.get("type") != "FeatureCollection":
        raise ValueError("taxi-zone geometry must be a GeoJSON FeatureCollection")
    return cast(dict[str, Any], payload)


def quantile_classes(values: Sequence[float], class_count: int = 5) -> list[int]:
    if class_count < 2:
        raise ValueError("at least two quantile classes are required")
    if not values:
        return []
    ordered = sorted(values)
    cuts = [ordered[min(len(ordered) - 1, len(ordered) * index // class_count)] for index in range(1, class_count)]
    return [min(bisect_right(cuts, value), class_count - 1) for value in values]


def _main() -> None:
    parser = argparse.ArgumentParser(description="Transform and simplify official TLC taxi-zone geometry")
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--source-crs", default="EPSG:2263")
    parser.add_argument("--tolerance", type=float, default=0.00015)
    args = parser.parse_args()
    preprocess_shapefile(
        args.source,
        args.destination,
        source_crs=args.source_crs,
        tolerance_degrees=args.tolerance,
    )


if __name__ == "__main__":
    _main()
