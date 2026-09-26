from fastapi import APIRouter, Depends
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.core.scope import parse_supermarket_scope
from app.schemas.price import ProductPricesResponse
from app.services import product_service

router = APIRouter(prefix="/api/v1/products", tags=["prices"])


@router.get("/{product_id}/prices", response_model=ProductPricesResponse)
def get_product_prices(
    product_id: str,
    scope: list[str] | None = Depends(parse_supermarket_scope),
    conn: Connection = Depends(get_db),
):
    return product_service.get_product_prices(conn, product_id, supermarket_codes=scope)
