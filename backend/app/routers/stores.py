from fastapi import APIRouter, Depends, Query
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.schemas.store import NearbyStoreListResponse, StoreListResponse
from app.services import store_service

router = APIRouter(prefix="/api/v1/stores", tags=["stores"])


@router.get("/nearby", response_model=NearbyStoreListResponse)
def list_stores_nearby(
    lat: float = Query(..., description="Latitud del usuario"),
    lon: float = Query(..., description="Longitud del usuario"),
    radius_km: float = Query(5.0, gt=0, le=100, description="Radio de búsqueda en kilómetros"),
    limit: int = Query(20, ge=1, le=100),
    conn: Connection = Depends(get_db),
):
    return store_service.list_stores_nearby(conn, lat, lon, radius_km, limit)


@router.get("", response_model=StoreListResponse)
def list_stores(
    supermarket: str | None = Query(None, description="Filtrar por código de supermercado"),
    conn: Connection = Depends(get_db),
):
    return store_service.list_stores(conn, supermarket)
