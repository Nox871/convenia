from fastapi import APIRouter, Depends
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.schemas.price import CompareResponse
from app.services import product_service

router = APIRouter(prefix="/api/products", tags=["comparison"])


@router.get("/{product_id}/compare", response_model=CompareResponse)
def compare_product(product_id: str, conn: Connection = Depends(get_db)):
    return product_service.compare_product(conn, product_id)
