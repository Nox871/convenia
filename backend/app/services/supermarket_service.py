from __future__ import annotations

from sqlalchemy.engine import Connection

from app.core.exceptions import NotFoundError
from app.repositories import supermarket_repository
from app.schemas.supermarket import Supermarket, SupermarketListResponse


def list_supermarkets(conn: Connection) -> SupermarketListResponse:
    rows = supermarket_repository.list_supermarkets(conn, only_active=True)
    return SupermarketListResponse(items=[Supermarket(**row) for row in rows])


def get_supermarket(conn: Connection, supermarket_id: int) -> Supermarket:
    row = supermarket_repository.get_supermarket(conn, supermarket_id)
    if row is None:
        raise NotFoundError(f"Supermercado '{supermarket_id}' no existe")
    return Supermarket(**row)
