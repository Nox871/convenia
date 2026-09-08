"""Lógica de negocio de listas de compra."""
from __future__ import annotations

from sqlalchemy.engine import Connection

from app.core.exceptions import InvalidParameterError, NotFoundError
from app.core.product_ref import encode_canonical_ref, encode_source_ref, parse_product_ref
from app.repositories import shopping_list_repository
from app.schemas.shopping_list import (
    DistributedPlanItem,
    DistributedPlanStop,
    ShoppingListCostResponse,
    ShoppingListDetail,
    ShoppingListDistributedResponse,
    ShoppingListItem,
    ShoppingListItemCreate,
    ShoppingListItemUpdate,
    ShoppingListListResponse,
    ShoppingListRename,
    ShoppingListSummary,
    SupermarketCost,
)


def create_list(conn: Connection, owner_ref: str, name: str) -> ShoppingListDetail:
    name = name.strip()
    if not name:
        raise InvalidParameterError("'name' no puede estar vacío")
    list_id = shopping_list_repository.create_list(conn, owner_ref, name)
    return get_list_detail(conn, list_id, owner_ref)


def list_lists(conn: Connection, owner_ref: str) -> ShoppingListListResponse:
    rows = shopping_list_repository.list_lists(conn, owner_ref)
    return ShoppingListListResponse(items=[ShoppingListSummary(**row) for row in rows])


def get_list_detail(conn: Connection, list_id: int, owner_ref: str) -> ShoppingListDetail:
    list_row = shopping_list_repository.get_list(conn, list_id, owner_ref)
    if list_row is None:
        raise NotFoundError(f"Lista '{list_id}' no existe")

    items_raw = shopping_list_repository.get_items(conn, list_id)
    items = [
        ShoppingListItem(
            id=row["id"],
            product_id=(
                encode_canonical_ref(row["product_id"])
                if row["product_id"] is not None
                else encode_source_ref(row["source_product_id"])
            ),
            name=row["name"],
            brand=row["brand"],
            image_url=row["image_url"],
            quantity=row["quantity"],
        )
        for row in items_raw
    ]

    return ShoppingListDetail(
        id=list_row["id"],
        name=list_row["name"],
        created_at=list_row["created_at"],
        updated_at=list_row["updated_at"],
        items=items,
    )


def rename_list(conn: Connection, list_id: int, owner_ref: str, payload: ShoppingListRename) -> ShoppingListDetail:
    name = payload.name.strip()
    if not name:
        raise InvalidParameterError("'name' no puede estar vacío")
    updated = shopping_list_repository.rename_list(conn, list_id, owner_ref, name)
    if not updated:
        raise NotFoundError(f"Lista '{list_id}' no existe")
    return get_list_detail(conn, list_id, owner_ref)


def delete_list(conn: Connection, list_id: int, owner_ref: str) -> None:
    deleted = shopping_list_repository.delete_list(conn, list_id, owner_ref)
    if not deleted:
        raise NotFoundError(f"Lista '{list_id}' no existe")


def add_item(
    conn: Connection, list_id: int, owner_ref: str, payload: ShoppingListItemCreate
) -> ShoppingListDetail:
    _ensure_list_owned(conn, list_id, owner_ref)

    try:
        ref = parse_product_ref(payload.product_id)
    except ValueError as exc:
        raise InvalidParameterError(str(exc)) from exc

    product_id = ref.numeric_id if ref.kind == "canonical" else None
    source_product_id = ref.numeric_id if ref.kind == "source" else None

    shopping_list_repository.add_item(conn, list_id, product_id, source_product_id, payload.quantity)
    shopping_list_repository.touch_list(conn, list_id)
    return get_list_detail(conn, list_id, owner_ref)


def update_item_quantity(
    conn: Connection, list_id: int, item_id: int, owner_ref: str, payload: ShoppingListItemUpdate
) -> ShoppingListDetail:
    _ensure_list_owned(conn, list_id, owner_ref)
    updated = shopping_list_repository.update_item_quantity(conn, item_id, list_id, payload.quantity)
    if not updated:
        raise NotFoundError(f"Ítem '{item_id}' no existe en la lista '{list_id}'")
    shopping_list_repository.touch_list(conn, list_id)
    return get_list_detail(conn, list_id, owner_ref)


def delete_item(conn: Connection, list_id: int, item_id: int, owner_ref: str) -> ShoppingListDetail:
    _ensure_list_owned(conn, list_id, owner_ref)
    deleted = shopping_list_repository.delete_item(conn, item_id, list_id)
    if not deleted:
        raise NotFoundError(f"Ítem '{item_id}' no existe en la lista '{list_id}'")
    shopping_list_repository.touch_list(conn, list_id)
    return get_list_detail(conn, list_id, owner_ref)


def get_cost(conn: Connection, list_id: int, owner_ref: str) -> ShoppingListCostResponse:
    """Costo estimado de la lista en cada supermercado activo, y cuál
    conviene para comprarla COMPLETA.

    "Conviene" sólo se calcula entre los supermercados donde la lista está
    COMPLETA (todos los ítems tienen precio) -- comparar totales parciales
    daría una falsa sensación de que un supermercado con muchos ítems sin
    dato es "más barato" simplemente porque le falta información.
    """
    _ensure_list_owned(conn, list_id, owner_ref)

    filas = shopping_list_repository.get_cost_breakdown_rows(conn, list_id)
    if not filas:
        return ShoppingListCostResponse(list_id=list_id, costs=[], best_supermarket_code=None)

    por_supermercado: dict[int, dict] = {}
    items_totales = len({fila["item_id"] for fila in filas})

    for fila in filas:
        sid = fila["supermarket_id"]
        if sid not in por_supermercado:
            por_supermercado[sid] = {
                "supermarket_code": fila["supermarket_code"],
                "supermarket_name": fila["supermarket_name"],
                "total": 0.0,
                "items_priced": 0,
            }
        if fila["price"] is not None:
            por_supermercado[sid]["total"] += float(fila["price"]) * fila["quantity"]
            por_supermercado[sid]["items_priced"] += 1

    costs = [
        SupermarketCost(
            supermarket_code=datos["supermarket_code"],
            supermarket_name=datos["supermarket_name"],
            total_cost=round(datos["total"], 2) if datos["items_priced"] > 0 else None,
            items_priced=datos["items_priced"],
            items_total=items_totales,
            is_complete=datos["items_priced"] == items_totales,
        )
        for datos in por_supermercado.values()
    ]
    costs.sort(key=lambda c: c.supermarket_name)

    completos = [c for c in costs if c.is_complete and c.total_cost is not None]
    best = min(completos, key=lambda c: c.total_cost) if completos else None

    return ShoppingListCostResponse(
        list_id=list_id,
        costs=costs,
        best_supermarket_code=best.supermarket_code if best else None,
    )


def get_distributed_plan(
    conn: Connection, list_id: int, owner_ref: str
) -> ShoppingListDistributedResponse:
    """Plan de compra distribuida: para cada ítem, el supermercado con el
    precio más bajo disponible -- reutiliza el mismo desglose ítem-por-
    supermercado que `get_cost` (sin query nueva). Ningún ítem sin precio en
    NINGÚN supermercado se fuerza a $0; se reporta aparte."""
    _ensure_list_owned(conn, list_id, owner_ref)

    items_raw = shopping_list_repository.get_items(conn, list_id)
    nombres_por_item = {row["id"]: row["name"] for row in items_raw}

    filas = shopping_list_repository.get_cost_breakdown_rows(conn, list_id)

    mejor_por_item: dict[int, dict] = {}
    for fila in filas:
        if fila["price"] is None:
            continue
        item_id = fila["item_id"]
        actual = mejor_por_item.get(item_id)
        if actual is None or float(fila["price"]) < actual["price"]:
            mejor_por_item[item_id] = {
                "price": float(fila["price"]),
                "quantity": fila["quantity"],
                "supermarket_code": fila["supermarket_code"],
                "supermarket_name": fila["supermarket_name"],
            }

    unpriced_item_ids = [
        item_id for item_id in nombres_por_item if item_id not in mejor_por_item
    ]

    paradas: dict[str, dict] = {}
    for item_id, datos in mejor_por_item.items():
        code = datos["supermarket_code"]
        if code not in paradas:
            paradas[code] = {
                "supermarket_code": code,
                "supermarket_name": datos["supermarket_name"],
                "items": [],
                "subtotal": 0.0,
            }
        subtotal_item = round(datos["price"] * datos["quantity"], 2)
        paradas[code]["items"].append(
            DistributedPlanItem(
                item_id=item_id,
                name=nombres_por_item[item_id],
                quantity=datos["quantity"],
                unit_price=datos["price"],
                subtotal=subtotal_item,
            )
        )
        paradas[code]["subtotal"] += subtotal_item

    stops = [
        DistributedPlanStop(
            supermarket_code=p["supermarket_code"],
            supermarket_name=p["supermarket_name"],
            items=p["items"],
            subtotal=round(p["subtotal"], 2),
        )
        for p in paradas.values()
    ]
    stops.sort(key=lambda s: s.supermarket_name)

    total_cost = round(sum(s.subtotal for s in stops), 2) if mejor_por_item else None

    return ShoppingListDistributedResponse(
        list_id=list_id,
        total_cost=total_cost,
        stops=stops,
        unpriced_item_ids=unpriced_item_ids,
    )


def _ensure_list_owned(conn: Connection, list_id: int, owner_ref: str) -> None:
    if shopping_list_repository.get_list(conn, list_id, owner_ref) is None:
        raise NotFoundError(f"Lista '{list_id}' no existe")
