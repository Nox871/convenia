from __future__ import annotations

import math

from sqlalchemy.engine import Connection

from app.core.config import settings
from app.core.exceptions import InvalidParameterError
from app.repositories import store_repository
from app.schemas.store import NearbyStore, NearbyStoreListResponse, PhysicalStore, StoreListResponse


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
