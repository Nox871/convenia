from fastapi import APIRouter, Depends
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.schemas.supermarket import Supermarket, SupermarketListResponse
from app.services import supermarket_service

router = APIRouter(prefix="/api/v1/supermarkets", tags=["supermarkets"])


@router.get("", response_model=SupermarketListResponse)
def list_supermarkets(conn: Connection = Depends(get_db)):
    return supermarket_service.list_supermarkets(conn)


@router.get("/{supermarket_id}", response_model=Supermarket)
def get_supermarket(supermarket_id: int, conn: Connection = Depends(get_db)):
    return supermarket_service.get_supermarket(conn, supermarket_id)
