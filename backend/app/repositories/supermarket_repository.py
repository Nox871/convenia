"""Acceso a datos de supermercados."""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection


_SELECT_WITH_LAST_RUN = """
    SELECT
        s.id, s.code, s.name, s.website_url, s.currency, s.is_active, s.created_at,
        last_run.finished_at AS last_successful_run_at
    FROM supermarkets s
    LEFT JOIN LATERAL (
        SELECT finished_at
        FROM scraper_runs
        WHERE supermarket_id = s.id AND status IN ('SUCCESS', 'SUCCESS_WITH_ERRORS')
        ORDER BY finished_at DESC
        LIMIT 1
    ) last_run ON TRUE
"""


def list_supermarkets(conn: Connection, only_active: bool = True) -> list[dict]:
    where_clause = "WHERE s.is_active = TRUE" if only_active else ""
    rows = conn.execute(
        text(f"{_SELECT_WITH_LAST_RUN} {where_clause} ORDER BY s.name ASC")
    ).mappings().all()
    return [dict(row) for row in rows]


def get_supermarket(conn: Connection, supermarket_id: int) -> dict | None:
    row = conn.execute(
        text(f"{_SELECT_WITH_LAST_RUN} WHERE s.id = :id"),
        {"id": supermarket_id},
    ).mappings().first()
    return dict(row) if row else None
