"""Acceso a datos de precios (price_observations)."""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection


def get_latest_offers(conn: Connection, source_product_ids: list[int]) -> list[dict]:
    """Última observación de precio DISPONIBLE por cada source_product dado.

    Usa `available = TRUE` explícitamente (regla de negocio: nunca comparar u
    ofrecer precios marcados como no disponibles) y ordena por precio
    ascendente para que el más barato quede primero.
    """
    if not source_product_ids:
        return []

    rows = conn.execute(
        text(
            """
            SELECT
                s.code AS supermarket_code,
                s.name AS supermarket_name,
                po.price,
                po.list_price,
                po.currency,
                po.available,
                po.observed_at,
                po.payment_methods
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            JOIN LATERAL (
                SELECT price, list_price, currency, available, observed_at, payment_methods
                FROM price_observations
                WHERE source_product_id = sp.id AND available = TRUE
                ORDER BY observed_at DESC
                LIMIT 1
            ) po ON TRUE
            WHERE sp.id = ANY(:ids)
            ORDER BY po.price ASC
            """
        ),
        {"ids": source_product_ids},
    ).mappings().all()

    return [dict(row) for row in rows]
