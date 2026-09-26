from fastapi import APIRouter, Depends, Query
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.routers.auth import require_admin
from app.schemas.store import (
    CoverageResponse,
    CreatePhysicalStore,
    NearbyStoreListResponse,
    PhysicalStore,
    StoreListResponse,
)
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


@router.get("/coverage", response_model=CoverageResponse)
def get_coverage(
    lat: float = Query(..., description="Latitud del usuario"),
    lon: float = Query(..., description="Longitud del usuario"),
    radius_km: float = Query(5.0, gt=0, le=100, description="Rango máximo en kilómetros"),
    conn: Connection = Depends(get_db),
):
    """Supermercados con al menos una tienda dentro del rango de la persona."""
    return store_service.get_coverage(conn, lat, lon, radius_km)


@router.get("", response_model=StoreListResponse)
def list_stores(
    supermarket: str | None = Query(None, description="Filtrar por código de supermercado"),
    conn: Connection = Depends(get_db),
):
    return store_service.list_stores(conn, supermarket)


@router.post("", response_model=PhysicalStore, status_code=201)
def create_store(
    payload: CreatePhysicalStore,
    conn: Connection = Depends(get_db),
    _admin=Depends(require_admin),
):
    """Alta manual de un establecimiento -- sólo administradores, para
    cubrir tiendas reales que el scraper de OpenStreetMap todavía no
    detecta."""
    return store_service.create_store(
        conn,
        supermarket_code=payload.supermarket_code,
        name=payload.name,
        address=payload.address,
        city=payload.city,
        latitude=payload.latitude,
        longitude=payload.longitude,
    )
