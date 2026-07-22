from __future__ import annotations

from datetime import datetime
from pathlib import Path

import polars as pl


def build_taxi_fixture() -> pl.DataFrame:
    return pl.DataFrame(
        {
            "VendorID": [1, 2, 99, 1, 1, 2],
            "tpep_pickup_datetime": [
                datetime(2023, 1, 1, 1, 0),
                datetime(2023, 1, 1, 1, 1),
                datetime(2023, 1, 2, 9, 0),
                datetime(2023, 1, 3, 10, 0),
                datetime(2023, 1, 4, 11, 0),
                datetime(2023, 1, 31, 23, 50),
            ],
            "tpep_dropoff_datetime": [
                datetime(2023, 1, 1, 1, 10),
                datetime(2023, 1, 1, 1, 11),
                datetime(2023, 1, 2, 9, 15),
                datetime(2023, 1, 3, 10, 5),
                datetime(2023, 1, 4, 11, 5),
                datetime(2023, 2, 1, 0, 10),
            ],
            "passenger_count": [1, 1, 1, 1, 1, 2],
            "trip_distance": [1.0, 2.0, 3.0, 0.0, 1.0, 4.0],
            "RatecodeID": [1, 1, 1, 1, 1, 1],
            "store_and_fwd_flag": ["N", "N", "N", "N", "N", "N"],
            "PULocationID": [1, 1, 1, 1, 1, 1],
            "DOLocationID": [1, 1, 1, 1, 1, 1],
            "payment_type": [1, 2, 99, 1, 1, 2],
            "fare_amount": [15.0, 30.0, 45.0, 10.0, -1.0, 60.0],
            "extra": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            "mta_tax": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            "tip_amount": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            "tolls_amount": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            "improvement_surcharge": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            "total_amount": [20.0, 35.0, 50.0, 10.0, 0.0, 65.0],
            "congestion_surcharge": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            "airport_fee": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        }
    )


def write_taxi_fixture(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    build_taxi_fixture().write_parquet(path)
    return path
