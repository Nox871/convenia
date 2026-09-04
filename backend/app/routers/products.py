from fastapi import APIRouter, Depends, Query
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.schemas.product import ProductDetail, ProductListResponse
from app.services import product_service

router = APIRouter(prefix="/api/products", tags=["products"])


@router.get("", response_model=ProductListResponse)
def list_products(
    q: str | None = Query(None, description="Texto de búsqueda por nombre de producto"),
    supermarket: str | None = Query(
        None, description="Filtrar por código de supermercado, ej. 'D1' o 'EXITO'"
    ),
    page: int = Query(1, ge=1, description="Página, 1-indexada"),
    limit: int = Query(20, ge=1, le=100, description="Resultados por página (máx. 100)"),
    conn: Connection = Depends(get_db),
):
    return product_service.list_products(conn, q=q, supermarket=supermarket, page=page, limit=limit)


@router.get("/{product_id}", response_model=ProductDetail)
def get_product(product_id: str, conn: Connection = Depends(get_db)):
    return product_service.get_product_detail(conn, product_id)
