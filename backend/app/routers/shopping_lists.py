from fastapi import APIRouter, Depends, Query
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.schemas.shopping_list import (
    ShoppingListCostResponse,
    ShoppingListCreate,
    ShoppingListDetail,
    ShoppingListDistributedResponse,
    ShoppingListItemCreate,
    ShoppingListItemUpdate,
    ShoppingListListResponse,
    ShoppingListRename,
)
from app.services import shopping_list_service

router = APIRouter(prefix="/api/v1/lists", tags=["lists"])


@router.get("", response_model=ShoppingListListResponse)
def list_lists(
    owner_ref: str = Query(..., description="Identificador de dispositivo"),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.list_lists(conn, owner_ref)


@router.post("", response_model=ShoppingListDetail, status_code=201)
def create_list(payload: ShoppingListCreate, conn: Connection = Depends(get_db)):
    return shopping_list_service.create_list(conn, payload.owner_ref, payload.name)


@router.get("/{list_id}", response_model=ShoppingListDetail)
def get_list(list_id: int, owner_ref: str = Query(...), conn: Connection = Depends(get_db)):
    return shopping_list_service.get_list_detail(conn, list_id, owner_ref)


@router.put("/{list_id}", response_model=ShoppingListDetail)
def rename_list(
    list_id: int,
    payload: ShoppingListRename,
    owner_ref: str = Query(...),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.rename_list(conn, list_id, owner_ref, payload)


@router.delete("/{list_id}", status_code=204)
def delete_list(list_id: int, owner_ref: str = Query(...), conn: Connection = Depends(get_db)):
    shopping_list_service.delete_list(conn, list_id, owner_ref)


@router.post("/{list_id}/items", response_model=ShoppingListDetail, status_code=201)
def add_item(
    list_id: int,
    payload: ShoppingListItemCreate,
    owner_ref: str = Query(...),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.add_item(conn, list_id, owner_ref, payload)


@router.put("/{list_id}/items/{item_id}", response_model=ShoppingListDetail)
def update_item(
    list_id: int,
    item_id: int,
    payload: ShoppingListItemUpdate,
    owner_ref: str = Query(...),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.update_item_quantity(conn, list_id, item_id, owner_ref, payload)


@router.delete("/{list_id}/items/{item_id}", response_model=ShoppingListDetail)
def delete_item(
    list_id: int, item_id: int, owner_ref: str = Query(...), conn: Connection = Depends(get_db)
):
    return shopping_list_service.delete_item(conn, list_id, item_id, owner_ref)


@router.get("/{list_id}/cost", response_model=ShoppingListCostResponse)
def get_cost(list_id: int, owner_ref: str = Query(...), conn: Connection = Depends(get_db)):
    return shopping_list_service.get_cost(conn, list_id, owner_ref)


@router.get("/{list_id}/cost/distributed", response_model=ShoppingListDistributedResponse)
def get_distributed_plan(
    list_id: int, owner_ref: str = Query(...), conn: Connection = Depends(get_db)
):
    return shopping_list_service.get_distributed_plan(conn, list_id, owner_ref)
