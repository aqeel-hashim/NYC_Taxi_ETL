"""Typed source contract and validation for TLC Yellow Taxi Parquet files."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import polars as pl

REQUIRED_COLUMNS: list[str] = [
    "VendorID",
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
    "passenger_count",
    "trip_distance",
    "RatecodeID",
    "store_and_fwd_flag",
    "PULocationID",
    "DOLocationID",
    "payment_type",
    "fare_amount",
    "extra",
    "mta_tax",
    "tip_amount",
    "tolls_amount",
    "improvement_surcharge",
    "total_amount",
    "congestion_surcharge",
    "airport_fee",
]


class ContractStatus(Enum):
    VALID = auto()
    MISSING_COLUMNS = auto()
    INCOMPATIBLE_TYPES = auto()
    ZERO_ROWS = auto()


@dataclass
class SourceContract:
    required_names: list[str] = field(default_factory=lambda: REQUIRED_COLUMNS.copy())
    extra_column_names: list[str] = field(default_factory=list)
    missing_required: list[str] = field(default_factory=list)
    incompatible_types: dict[str, tuple[str, str]] = field(default_factory=dict)
    source_row_count: int = 0
    status: ContractStatus = ContractStatus.VALID

    @property
    def is_valid(self) -> bool:
        return self.status == ContractStatus.VALID


def validate_contract(df: pl.DataFrame) -> SourceContract:
    """Validate that a DataFrame meets the source contract."""
    present = set(df.columns)
    required_set = set(REQUIRED_COLUMNS)

    missing = sorted(required_set - present)
    extra = sorted(present - required_set)

    contract = SourceContract(extra_column_names=extra)

    if missing:
        contract.missing_required = missing
        contract.status = ContractStatus.MISSING_COLUMNS
        return contract

    expected_types: dict[str, str] = {
        "VendorID": "Int",
        "passenger_count": "Int",
        "trip_distance": "Float",
        "RatecodeID": "Int",
        "PULocationID": "Int",
        "DOLocationID": "Int",
        "payment_type": "Int",
        "fare_amount": "Float",
        "extra": "Float",
        "mta_tax": "Float",
        "tip_amount": "Float",
        "tolls_amount": "Float",
        "improvement_surcharge": "Float",
        "total_amount": "Float",
        "congestion_surcharge": "Float",
        "airport_fee": "Float",
    }

    incompatible: dict[str, tuple[str, str]] = {}
    for col, exp in expected_types.items():
        actual = str(df.schema.get(col, ""))
        if actual and exp not in actual and actual != "Null":
            incompatible[col] = (exp, actual)

    if incompatible:
        contract.incompatible_types = incompatible
        contract.status = ContractStatus.INCOMPATIBLE_TYPES
        return contract

    contract.source_row_count = len(df)
    if contract.source_row_count == 0:
        contract.status = ContractStatus.ZERO_ROWS

    return contract
