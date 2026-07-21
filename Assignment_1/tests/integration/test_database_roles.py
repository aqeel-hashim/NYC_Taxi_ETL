from __future__ import annotations

import os

import psycopg
import pytest

from alembic import command
from alembic.config import Config


def test_dashboard_role_can_read_not_write() -> None:
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        pytest.skip("TEST_DATABASE_URL is required for role tests")
    config = Config("alembic.ini")
    config.set_main_option("sqlalchemy.url", url)
    command.downgrade(config, "base")
    command.upgrade(config, "head")

    with psycopg.connect(url.replace("postgresql+psycopg://", "postgresql://")) as conn:
        conn.execute("SET ROLE taxi_dashboard_readonly")
        conn.execute("SELECT count(*) FROM analytics.dashboard_revenue_by_payment_type").fetchone()
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute(
                """
                INSERT INTO warehouse.dim_payment_type (business_key, label, observed_from, is_current)
                VALUES (9, 'x', now(), true)
                """
            )
