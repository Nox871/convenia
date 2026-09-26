from fastapi import APIRouter, Depends, Query
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.core.ownership import resolve_owner_ref
from app.core.scope import parse_supermarket_scope
from app.routers.auth import get_current_user, get_optional_user
from app.schemas.auth import UserPublic
from app.schemas.shopping_list import (
    ShoppingListClaim,
    ShoppingListClaimResponse,
    ShoppingListCostResponse,
    ShoppingListCreate,
    ShoppingListDetail,
    ShoppingListDistributedResponse,
    ShoppingListItemCreate,
    ShoppingListItemUpdate,
    ShoppingListListResponse,
    ShoppingListBudget,
    ShoppingListRename,
    SwapSuggestionsResponse,
)
from app.services import shopping_list_service

router = APIRouter(prefix="/api/v1/lists", tags=["lists"])


def owner_ref_dependency(
    owner_ref: str = Query(..., description="Identificador de dispositivo (se ignora con sesión iniciada)"),
    user: UserPublic | None = Depends(get_optional_user),
) -> str:
    """Dueño efectivo de las listas: la cuenta si hay sesión, si no el dispositivo."""
    return resolve_owner_ref(owner_ref, user.id if user else None)


@router.get("", response_model=ShoppingListListResponse)
def list_lists(
    owner_ref: str = Depends(owner_ref_dependency),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.list_lists(conn, owner_ref)


@router.post("", response_model=ShoppingListDetail, status_code=201)
def create_list(
    payload: ShoppingListCreate,
    user: UserPublic | None = Depends(get_optional_user),
    conn: Connection = Depends(get_db),
):
    owner_ref = resolve_owner_ref(payload.owner_ref, user.id if user else None)
    return shopping_list_service.create_list(conn, owner_ref, payload.name)


@router.post("/claim", response_model=ShoppingListClaimResponse)
def claim_device_lists(
    payload: ShoppingListClaim,
    user: UserPublic = Depends(get_current_user),
    conn: Connection = Depends(get_db),
):
    """Pasa a la cuenta las listas que se hicieron en este dispositivo como
    invitado, para no perderlas al iniciar sesión."""
    return shopping_list_service.claim_device_lists(conn, payload.owner_ref, user.id)


@router.get("/{list_id}", response_model=ShoppingListDetail)
def get_list(list_id: int, owner_ref: str = Depends(owner_ref_dependency), conn: Connection = Depends(get_db)):
    return shopping_list_service.get_list_detail(conn, list_id, owner_ref)


@router.put("/{list_id}", response_model=ShoppingListDetail)
def rename_list(
    list_id: int,
    payload: ShoppingListRename,
    owner_ref: str = Depends(owner_ref_dependency),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.rename_list(conn, list_id, owner_ref, payload)


@router.delete("/{list_id}", status_code=204)
def delete_list(list_id: int, owner_ref: str = Depends(owner_ref_dependency), conn: Connection = Depends(get_db)):
    shopping_list_service.delete_list(conn, list_id, owner_ref)


@router.post("/{list_id}/items", response_model=ShoppingListDetail, status_code=201)
def add_item(
    list_id: int,
    payload: ShoppingListItemCreate,
    owner_ref: str = Depends(owner_ref_dependency),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.add_item(conn, list_id, owner_ref, payload)


@router.put("/{list_id}/budget", response_model=ShoppingListDetail)
def set_budget(
    list_id: int,
    payload: ShoppingListBudget,
    owner_ref: str = Depends(owner_ref_dependency),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.set_budget(conn, list_id, owner_ref, payload)


@router.put("/{list_id}/items/{item_id}", response_model=ShoppingListDetail)
def update_item(
    list_id: int,
    item_id: int,
    payload: ShoppingListItemUpdate,
    owner_ref: str = Depends(owner_ref_dependency),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.update_item_quantity(conn, list_id, item_id, owner_ref, payload)


@router.delete("/{list_id}/items/{item_id}", response_model=ShoppingListDetail)
def delete_item(
    list_id: int, item_id: int, owner_ref: str = Depends(owner_ref_dependency), conn: Connection = Depends(get_db)
):
    return shopping_list_service.delete_item(conn, list_id, item_id, owner_ref)


@router.get("/{list_id}/cost", response_model=ShoppingListCostResponse)
def get_cost(
    list_id: int,
    owner_ref: str = Depends(owner_ref_dependency),
    scope: list[str] | None = Depends(parse_supermarket_scope),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.get_cost(conn, list_id, owner_ref, supermarket_codes=scope)


@router.get("/{list_id}/cost/distributed", response_model=ShoppingListDistributedResponse)
def get_distributed_plan(
    list_id: int,
    owner_ref: str = Depends(owner_ref_dependency),
    scope: list[str] | None = Depends(parse_supermarket_scope),
    conn: Connection = Depends(get_db),
):
    return shopping_list_service.get_distributed_plan(
        conn, list_id, owner_ref, supermarket_codes=scope
    )


@router.get("/{list_id}/savings", response_model=SwapSuggestionsResponse)
def get_swap_suggestions(
    list_id: int,
    owner_ref: str = Depends(owner_ref_dependency),
    scope: list[str] | None = Depends(parse_supermarket_scope),
    conn: Connection = Depends(get_db),
):
    """Sustitutos más baratos, del mismo tipo y tamaño, para bajar el costo de
    la lista (por ejemplo cuando se pasa del presupuesto)."""
    return shopping_list_service.get_swap_suggestions(conn, list_id, owner_ref, supermarket_codes=scope)
