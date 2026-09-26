from __future__ import annotations

import math

from sqlalchemy.engine import Connection

from app.core.config import settings
from app.core.exceptions import InvalidParameterError, NotFoundError
from app.repositories import store_repository
from app.schemas.store import (
    CoverageResponse,
    NearbyStore,
    NearbyStoreListResponse,
    PhysicalStore,
    StoreListResponse,
    SupermarketCoverage,
)


def create_store(
    conn: Connection,
    supermarket_code: str,
    name: str,
    address: str | None,
    city: str | None,
    latitude: float,
    longitude: float,
) -> PhysicalStore:
    row = store_repository.create_store(
        conn,
        supermarket_code=supermarket_code.strip().upper(),
        name=name.strip(),
        address=address.strip() if address else None,
        city=city.strip() if city else None,
        latitude=latitude,
        longitude=longitude,
    )
    if row is None:
        raise NotFoundError(f"Supermercado '{supermarket_code}' no existe")
    return PhysicalStore(**row)


def list_stores(conn: Connection, supermarket: str | None) -> StoreListResponse:
    supermarket_code = supermarket.strip().upper() if supermarket else None
    rows = store_repository.list_stores(conn, supermarket_code)
    return StoreListResponse(items=[PhysicalStore(**row) for row in rows])


def list_stores_nearby(
    conn: Connection, latitude: float, longitude: float, radius_km: float, limit: int
) -> NearbyStoreListResponse:
    if not (-90 <= latitude <= 90) or not (-180 <= longitude <= 180):
        raise InvalidParameterError("Coordenadas fuera de rango")
    if radius_km <= 0:
        raise InvalidParameterError("'radius_km' debe ser > 0")

    rows = store_repository.list_stores_nearby(conn, latitude, longitude, radius_km, limit)
    items = [
        NearbyStore(
            **row,
            walking_minutes=math.ceil(row["distance_km"] / settings.walking_speed_kmh * 60),
        )
        for row in rows
    ]
    return NearbyStoreListResponse(items=items)


def get_coverage(conn: Connection, latitude: float, longitude: float, radius_km: float) -> CoverageResponse:
    """Qué supermercados tienen al menos una tienda dentro del rango. Un
    supermercado sin ninguna tienda registrada NO está al alcance: sin una
    sede conocida no hay forma de asegurar que la persona pueda comprar ahí."""
    filas = store_repository.get_coverage(conn, latitude, longitude, radius_km)
    return CoverageResponse(
        radius_km=radius_km,
        supermarkets=[
            SupermarketCoverage(
                code=f["code"],
                name=f["name"],
                in_range=f["stores_in_range"] > 0,
                stores_in_range=f["stores_in_range"],
                nearest_km=round(float(f["nearest_km"]), 1) if f["nearest_km"] is not None else None,
            )
            for f in filas
        ],
    )
