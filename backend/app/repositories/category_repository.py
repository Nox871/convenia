"""Acceso a datos de categorías (source_categories).

La normalización a "categoría común" (bucket) se hace en Python al vuelo con
`obtener_bucket` (mismo clasificador que usa el scraper/ETL) en vez de en
SQL, porque la lista de palabras clave vive en código, no en la base.
"""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection


def list_categories_raw(conn: Connection) -> list[dict]:
    """Categorías con al menos un producto ACTIVE, con el conteo de
    productos activos que tienen."""
    rows = conn.execute(
        text(
            """
            SELECT
                sc.id,
                sc.name_raw,
                s.code AS supermarket_code,
                COUNT(sp.id) FILTER (WHERE sp.status = 'ACTIVE') AS active_products_count
            FROM source_categories sc
            JOIN supermarkets s ON s.id = sc.supermarket_id
            LEFT JOIN source_products sp ON sp.source_category_id = sc.id
            GROUP BY sc.id, sc.name_raw, s.code
            HAVING COUNT(sp.id) FILTER (WHERE sp.status = 'ACTIVE') > 0
            ORDER BY sc.name_raw ASC
            """
        )
    ).mappings().all()
    return [dict(row) for row in rows]
