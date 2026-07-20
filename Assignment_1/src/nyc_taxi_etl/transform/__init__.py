"""Transform package."""

from nyc_taxi_etl.transform.trips import TransformResult, transform

__all__ = [
    "TransformResult",
    "transform",
]
