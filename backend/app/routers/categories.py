from fastapi import APIRouter, Depends
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.schemas.category import CategoryListResponse
from app.services import category_service

router = APIRouter(prefix="/api/v1/categories", tags=["categories"])


@router.get("", response_model=CategoryListResponse)
def list_categories(conn: Connection = Depends(get_db)):
    return category_service.list_categories(conn)
