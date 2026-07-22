from pathlib import Path


def test_readonly_role_sees_views_not_ops_or_warehouse() -> None:
    source = Path("alembic/versions/0004_dashboard_interfaces.py").read_text()
    assert "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA warehouse, analytics, ops" in source
    assert "REVOKE ALL PRIVILEGES ON SCHEMA warehouse, ops" in source
    assert "GRANT SELECT ON" in source
    assert "analytics.dashboard_trip_metrics" in source
    assert "default_transaction_read_only = on" in source
    assert "statement_timeout = '1500ms'" in source


def test_explorer_has_canonical_keyset_index() -> None:
    source = Path("alembic/versions/0004_dashboard_interfaces.py").read_text()
    assert '"ix_fact_taxi_trips_explorer_keyset": "pickup_at_local, trip_key"' in source
    for indexed_filter in ("pickup_zone_key", "dropoff_zone_key", "payment_type_key", "vendor_key", "rate_code_key"):
        assert indexed_filter in source
    assert "WHERE has_quality_issue" in source
