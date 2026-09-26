"""Acceso a datos de establecimientos físicos (physical_stores)."""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection


def create_store(
    conn: Connection,
    supermarket_code: str,
    name: str,
    address: str | None,
    city: str | None,
    latitude: float,
    longitude: float,
) -> dict | None:
    """Inserta un establecimiento manual (sin `external_id`: no viene de
    OpenStreetMap). Devuelve `None` si `supermarket_code` no existe -- el
    servicio decide qué error HTTP corresponde."""
    supermarket = conn.execute(
        text("SELECT id, code, name FROM supermarkets WHERE code = :code"),
        {"code": supermarket_code},
    ).mappings().first()
    if supermarket is None:
        return None

    row = conn.execute(
        text(
            """
            INSERT INTO physical_stores (supermarket_id, name, address, city, latitude, longitude)
            VALUES (:supermarket_id, :name, :address, :city, :latitude, :longitude)
            RETURNING id, name, address, city, latitude, longitude
            """
        ),
        {
            "supermarket_id": supermarket["id"],
            "name": name,
            "address": address,
            "city": city,
            "latitude": latitude,
            "longitude": longitude,
        },
    ).mappings().first()
    conn.commit()

    return {
        **dict(row),
        "supermarket_code": supermarket["code"],
        "supermarket_name": supermarket["name"],
    }


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


def get_coverage(conn: Connection, latitude: float, longitude: float, radius_km: float) -> list[dict]:
    """Por cada supermercado activo: cuántas de sus tiendas caen dentro de
    `radius_km` y a qué distancia queda la más cercana (de cualquier
    distancia, para poder decir "la más cercana está a X km")."""
    rows = conn.execute(
        text(
            """
            SELECT
                s.code, s.name,
                COUNT(*) FILTER (WHERE d.distance_km <= :radius_km) AS stores_in_range,
                MIN(d.distance_km) AS nearest_km
            FROM supermarkets s
            LEFT JOIN LATERAL (
                SELECT (
                    6371 * acos(
                        LEAST(1.0, GREATEST(-1.0,
                            cos(radians(:lat)) * cos(radians(ps.latitude))
                            * cos(radians(ps.longitude) - radians(:lon))
                            + sin(radians(:lat)) * sin(radians(ps.latitude))
                        ))
                    )
                ) AS distance_km
                FROM physical_stores ps
                WHERE ps.supermarket_id = s.id AND ps.is_active = TRUE
                  AND ps.latitude IS NOT NULL AND ps.longitude IS NOT NULL
            ) d ON TRUE
            WHERE s.is_active = TRUE
            GROUP BY s.code, s.name
            ORDER BY s.name
            """
        ),
        {"lat": latitude, "lon": longitude, "radius_km": radius_km},
    ).mappings().all()
    return [dict(row) for row in rows]
