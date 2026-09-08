from fastapi import APIRouter, Depends, Query
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.schemas.price import PriceHistoryMonthlyResponse, PriceHistoryResponse
from app.services import product_service

router = APIRouter(prefix="/api/v1/products", tags=["history"])


@router.get("/{product_id}/history/monthly", response_model=PriceHistoryMonthlyResponse)
def get_product_price_history_monthly(product_id: str, conn: Connection = Depends(get_db)):
    return product_service.get_price_history_monthly(conn, product_id)


@router.get("/{product_id}/history", response_model=PriceHistoryResponse)
def get_product_price_history(
    product_id: str,
    month: str | None = Query(None, description="Filtrar a un mes 'YYYY-MM' (drill-down)"),
    page: int = Query(1, ge=1, description="Página, 1-indexada"),
    limit: int = Query(20, ge=1, le=100, description="Observaciones por página (máx. 100)"),
    conn: Connection = Depends(get_db),
):
    return product_service.get_price_history(conn, product_id, page=page, limit=limit, month=month)
