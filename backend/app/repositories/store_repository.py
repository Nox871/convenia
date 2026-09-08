"""Acceso a datos de establecimientos físicos (physical_stores)."""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection


def list_stores(conn: Connection, supermarket_code: str | None) -> list[dict]:
    filters = ["ps.is_active = TRUE"]
    params: dict = {}
    if supermarket_code:
        filters.append("s.code = :supermarket_code")
        params["supermarket_code"] = supermarket_code

    where_clause = " AND ".join(filters)
    rows = conn.execute(
        text(
            f"""
            SELECT ps.id, s.code AS supermarket_code, s.name AS supermarket_name,
                   ps.name, ps.address, ps.city, ps.latitude, ps.longitude
            FROM physical_stores ps
            JOIN supermarkets s ON s.id = ps.supermarket_id
            WHERE {where_clause}
            ORDER BY ps.city ASC, ps.name ASC
            """
        ),
        params,
    ).mappings().all()
    return [dict(row) for row in rows]


def list_stores_nearby(
    conn: Connection, latitude: float, longitude: float, radius_km: float, limit: int
) -> list[dict]:
    """Establecimientos activos dentro de `radius_km`, ordenados por
    distancia. Fórmula de Haversine calculada en SQL (sin PostGIS: el
    volumen esperado de `physical_stores` no lo justifica todavía)."""
    rows = conn.execute(
        text(
            """
            SELECT * FROM (
                SELECT
                    ps.id, s.code AS supermarket_code, s.name AS supermarket_name,
                    ps.name, ps.address, ps.city, ps.latitude, ps.longitude,
                    (
                        6371 * acos(
                            LEAST(1.0, GREATEST(-1.0,
                                cos(radians(:lat)) * cos(radians(ps.latitude))
                                * cos(radians(ps.longitude) - radians(:lon))
                                + sin(radians(:lat)) * sin(radians(ps.latitude))
                            ))
                        )
                    ) AS distance_km
                FROM physical_stores ps
                JOIN supermarkets s ON s.id = ps.supermarket_id
                WHERE ps.is_active = TRUE
                  AND ps.latitude IS NOT NULL AND ps.longitude IS NOT NULL
            ) con_distancia
            WHERE distance_km <= :radius_km
            ORDER BY distance_km ASC
            LIMIT :limit
            """
        ),
        {"lat": latitude, "lon": longitude, "radius_km": radius_km, "limit": limit},
    ).mappings().all()
    return [dict(row) for row in rows]
