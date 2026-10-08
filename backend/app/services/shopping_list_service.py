"""Lógica de negocio de listas de compra."""
from __future__ import annotations

import time

from sqlalchemy.engine import Connection

from app.core.exceptions import InvalidParameterError, NotFoundError
from app.core.ownership import USER_PREFIX
from app.core.product_ref import encode_canonical_ref, encode_source_ref, parse_product_ref
from app.core.swap_matching import (
    Producto,
    distancia_de_tamano,
    es_mas_barato,
    parecido,
    es_mismo_producto,
    puede_sustituir,
)
from app.repositories import price_repository, shopping_list_repository
from app.schemas.shopping_list import (
    SingleStoreOption,
    SingleStoreReplacement,
    SingleStoreResponse,
    DistributedPlanItem,
    DistributedPlanStop,
    ShoppingListBudget,
    ShoppingListClaimResponse,
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
    SwapAlternative,
    SwapSuggestion,
    SwapSuggestionsResponse,
)


def claim_device_lists(conn: Connection, device_ref: str, user_id: int) -> ShoppingListClaimResponse:
    """Al iniciar sesión, las listas hechas como invitado en este dispositivo
    pasan a la cuenta. Sólo se reclaman las de un identificador de dispositivo
    (nunca las de otra cuenta)."""
    if device_ref.startswith(USER_PREFIX):
        raise InvalidParameterError("Identificador de dispositivo inválido")
    claimed = shopping_list_repository.claim_device_lists(conn, device_ref, user_id)
    return ShoppingListClaimResponse(claimed=claimed)


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
        budget=list_row.get("budget"),
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


def set_budget(
    conn: Connection, list_id: int, owner_ref: str, payload: ShoppingListBudget
) -> ShoppingListDetail:
    updated = shopping_list_repository.set_budget(conn, list_id, owner_ref, payload.budget)
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


def get_cost(
    conn: Connection, list_id: int, owner_ref: str, supermarket_codes: list[str] | None = None
) -> ShoppingListCostResponse:
    """Costo estimado de la lista en cada supermercado activo, y cuál
    conviene para comprarla COMPLETA.

    "Conviene" sólo se calcula entre los supermercados donde la lista está
    COMPLETA (todos los ítems tienen precio) -- comparar totales parciales
    daría una falsa sensación de que un supermercado con muchos ítems sin
    dato es "más barato" simplemente porque le falta información.
    """
    _ensure_list_owned(conn, list_id, owner_ref)

    filas = shopping_list_repository.get_cost_breakdown_rows(conn, list_id, supermarket_codes)
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
                "missing_item_ids": [],
            }
        if fila["price"] is not None:
            por_supermercado[sid]["total"] += float(fila["price"]) * fila["quantity"]
            por_supermercado[sid]["items_priced"] += 1
        else:
            por_supermercado[sid]["missing_item_ids"].append(fila["item_id"])

    costs = [
        SupermarketCost(
            supermarket_code=datos["supermarket_code"],
            supermarket_name=datos["supermarket_name"],
            total_cost=round(datos["total"], 2) if datos["items_priced"] > 0 else None,
            items_priced=datos["items_priced"],
            items_total=items_totales,
            is_complete=datos["items_priced"] == items_totales,
            missing_item_ids=sorted(set(datos["missing_item_ids"])),
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
    conn: Connection, list_id: int, owner_ref: str, supermarket_codes: list[str] | None = None
) -> ShoppingListDistributedResponse:
    """Plan de compra distribuida: para cada ítem, el supermercado con el
    precio más bajo disponible -- reutiliza el mismo desglose ítem-por-
    supermercado que `get_cost` (sin query nueva). Ningún ítem sin precio en
    NINGÚN supermercado se fuerza a $0; se reporta aparte."""
    _ensure_list_owned(conn, list_id, owner_ref)

    items_raw = shopping_list_repository.get_items(conn, list_id)
    nombres_por_item = {row["id"]: row["name"] for row in items_raw}

    filas = shopping_list_repository.get_cost_breakdown_rows(conn, list_id, supermarket_codes)

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


MAX_SWAP_SUGGESTIONS = 5

# El índice de candidatos sólo cambia cuando corre el ETL (una vez al día): se
# guarda en memoria unos minutos por conjunto de supermercados.
_SWAP_CACHE_SECONDS = 300
_swap_cache: dict[tuple | None, tuple[float, dict[str, list[tuple[dict, Producto]]]]] = {}


def _swap_candidates(
    conn: Connection, supermarket_codes: list[str] | None
) -> dict[str, list[tuple[dict, Producto]]]:
    """Productos con precio vigente, indexados por su primera palabra base, para
    no comparar cada ítem contra todo el catálogo."""
    key = None if supermarket_codes is None else tuple(sorted(supermarket_codes))
    cached = _swap_cache.get(key)
    if cached is not None and time.monotonic() - cached[0] < _SWAP_CACHE_SECONDS:
        return cached[1]

    por_primera_palabra: dict[str, list[tuple[dict, Producto]]] = {}
    for oferta in price_repository.list_current_offers(conn, supermarket_codes):
        producto = Producto(nombre=oferta["name"], marca=oferta["brand"])
        base = producto.base
        if base:
            por_primera_palabra.setdefault(base[0], []).append((oferta, producto))
    _swap_cache[key] = (time.monotonic(), por_primera_palabra)
    return por_primera_palabra


def get_swap_suggestions(
    conn: Connection, list_id: int, owner_ref: str, supermarket_codes: list[str] | None = None
) -> SwapSuggestionsResponse:
    """Cambios que bajarían el costo de la lista: para cada ítem, un producto
    del MISMO tipo y tamaño parecido que sea al menos 5 % más barato, entre los
    supermercados al alcance. Nunca sugiere un producto de otra clase (ver
    `app.core.swap_matching`), y no inventa nada: si no hay sustituto claro, el
    ítem simplemente no aparece."""
    _ensure_list_owned(conn, list_id, owner_ref)

    items = shopping_list_repository.get_items(conn, list_id)
    filas = shopping_list_repository.get_cost_breakdown_rows(conn, list_id, supermarket_codes)

    # Mejor (más barato) precio actual de cada ítem entre los supermercados al alcance.
    actual_por_item: dict[int, dict] = {}
    for fila in filas:
        if fila["price"] is None:
            continue
        precio = float(fila["price"])
        previo = actual_por_item.get(fila["item_id"])
        if previo is None or precio < previo["price"]:
            actual_por_item[fila["item_id"]] = {"price": precio, "supermarket_name": fila["supermarket_name"]}

    por_primera_palabra = _swap_candidates(conn, supermarket_codes)

    sugerencias: list[SwapSuggestion] = []
    for item in items:
        actual = actual_por_item.get(item["id"])
        if actual is None:
            continue
        original = Producto(nombre=item["name"], marca=item.get("brand"))
        base = original.base
        if not base:
            continue

        mejor: dict | None = None
        for oferta, candidato in por_primera_palabra.get(base[0], []):
            if not es_mas_barato(actual["price"], oferta["price"]):
                continue
            if not puede_sustituir(original, candidato):
                continue
            if mejor is None or oferta["price"] < mejor["price"]:
                mejor = oferta
        if mejor is None:
            continue

        sugerencias.append(
            SwapSuggestion(
                item_id=item["id"],
                item_name=item["name"],
                quantity=item["quantity"],
                current_unit_price=actual["price"],
                current_supermarket_name=actual["supermarket_name"],
                alternative=SwapAlternative(
                    product_id=encode_source_ref(mejor["source_product_id"]),
                    name=mejor["name"],
                    brand=mejor["brand"],
                    image_url=mejor["image_url"],
                    unit_price=mejor["price"],
                    supermarket_code=mejor["supermarket_code"],
                    supermarket_name=mejor["supermarket_name"],
                ),
                saving_total=round((actual["price"] - mejor["price"]) * item["quantity"], 2),
            )
        )

    sugerencias.sort(key=lambda s: s.saving_total, reverse=True)
    sugerencias = sugerencias[:MAX_SWAP_SUGGESTIONS]
    return SwapSuggestionsResponse(
        list_id=list_id,
        suggestions=sugerencias,
        total_saving=round(sum(s.saving_total for s in sugerencias), 2),
    )


# Al completar una lista en UN supermercado la persona acepta otra marca y un tamaño
# un poco distinto, pero nunca otro tipo de producto: la tolerancia de tamaño es
# mayor que la de "cómo ahorrar", y el parecido del tipo sigue siendo el mismo.
TOLERANCIA_TAMANO_UNA_TIENDA = 0.35


def _raiz(palabra: str) -> str:
    """papas -> papa, cafes -> cafe: para reconocer el mismo tipo en singular y plural."""
    return palabra[:-1] if len(palabra) > 4 and palabra.endswith("s") else palabra


def _mejor_sustituto(
    item: dict, codigo_tienda: str, candidatos: dict, precio_referencia: float | None = None
) -> dict | None:
    """El producto de ESA tienda que mejor reemplaza a `item`. Siempre intenta
    encontrar uno, en tres niveles de más a menos estricto:

    1. mismo tipo de producto (nombre muy parecido) y tamaño parecido;
    2. el mismo tipo de producto aunque la marca, el sabor o el tamaño cambien
       (otro pollo, otro café, otras papas);
    3. el mismo tipo en cualquier presentación.

    Dentro de un nivel gana el más parecido y, entre iguales, el de precio más
    cercano al que la persona ya tenía: si armó una lista económica no se le
    sube a un producto premium, y al revés."""
    original = Producto(nombre=item["name"], marca=item.get("brand"))
    base = original.base
    if not base:
        return None
    raiz = _raiz(base[0])
    de_la_tienda = [
        (o, c) for lista in candidatos.values() for o, c in lista if o["supermarket_code"] == codigo_tienda
    ]

    def cercania_precio(oferta: dict) -> float:
        if not precio_referencia:
            return oferta["price"]
        return abs(oferta["price"] - precio_referencia) / precio_referencia

    def elegir(validos) -> dict | None:
        mejor, mejor_clave = None, None
        for oferta, candidato in validos:
            clave = (
                -round(parecido(original.base, candidato.base), 1),
                round(cercania_precio(oferta), 1),
                distancia_de_tamano(original.cantidad, candidato.cantidad),
            )
            if mejor_clave is None or clave < mejor_clave:
                mejor, mejor_clave = oferta, clave
        return mejor

    estricto = [
        (o, c) for o, c in candidatos.get(base[0], [])
        if o["supermarket_code"] == codigo_tienda
        and puede_sustituir(original, c, TOLERANCIA_TAMANO_UNA_TIENDA)
    ]
    if (hallado := elegir(estricto)) is not None:
        return hallado

    mismo_tipo = [
        (o, c) for o, c in de_la_tienda
        if any(_raiz(w) == raiz for w in c.base) and not es_mismo_producto(original, c)
    ]
    misma_dimension = [
        (o, c) for o, c in mismo_tipo
        if original.cantidad is None
        or (c.cantidad is not None and c.cantidad.dimension == original.cantidad.dimension)
    ]
    return elegir(misma_dimension) or elegir(mismo_tipo)


def get_single_store_options(
    conn: Connection, list_id: int, owner_ref: str, supermarket_codes: list[str] | None = None
) -> SingleStoreResponse:
    """Cómo comprar la lista en UN solo supermercado: para cada tienda al alcance
    que tenga algo de la lista, qué le falta y con qué producto parecido de esa
    misma tienda se puede reemplazar, y cuánto costaría la lista completa así.

    No inventa nada: un ítem sin reemplazo claro queda sin sustituto y la tienda
    deja de ser "completable". Nada se cambia solo; la app aplica los reemplazos
    que la persona confirme."""
    _ensure_list_owned(conn, list_id, owner_ref)

    items = shopping_list_repository.get_items(conn, list_id)
    filas = shopping_list_repository.get_cost_breakdown_rows(conn, list_id, supermarket_codes)
    if not items or not filas:
        return SingleStoreResponse(list_id=list_id, options=[])

    precios: dict[tuple[int, str], float] = {}
    tiendas: dict[str, str] = {}
    for fila in filas:
        tiendas[fila["supermarket_code"]] = fila["supermarket_name"]
        if fila["price"] is not None:
            precios[(fila["item_id"], fila["supermarket_code"])] = float(fila["price"])

    candidatos = _swap_candidates(conn, supermarket_codes)

    opciones: list[SingleStoreOption] = []
    for codigo, nombre in tiendas.items():
        con_precio = 0
        total_actual = 0.0
        reemplazos: list[SingleStoreReplacement] = []
        completable = True
        total_con_reemplazos = 0.0

        for item in items:
            precio = precios.get((item["id"], codigo))
            if precio is not None:
                con_precio += 1
                total_actual += precio * item["quantity"]
                total_con_reemplazos += precio * item["quantity"]
                continue
            conocidos = [v for (iid, _c), v in precios.items() if iid == item["id"]]
            referencia = sum(conocidos) / len(conocidos) if conocidos else None
            sustituto = _mejor_sustituto(item, codigo, candidatos, referencia)
            alternativa = None
            if sustituto is None:
                completable = False
            else:
                total_con_reemplazos += sustituto["price"] * item["quantity"]
                alternativa = SwapAlternative(
                    product_id=encode_source_ref(sustituto["source_product_id"]),
                    name=sustituto["name"],
                    brand=sustituto["brand"],
                    image_url=sustituto["image_url"],
                    unit_price=sustituto["price"],
                    supermarket_code=sustituto["supermarket_code"],
                    supermarket_name=sustituto["supermarket_name"],
                )
            reemplazos.append(
                SingleStoreReplacement(
                    item_id=item["id"], item_name=item["name"], quantity=item["quantity"], substitute=alternativa
                )
            )

        if con_precio == 0:
            continue  # una tienda que no tiene nada de la lista no es una opción realista
        opciones.append(
            SingleStoreOption(
                supermarket_code=codigo,
                supermarket_name=nombre,
                items_total=len(items),
                items_priced=con_precio,
                current_total=round(total_actual, 2),
                completable=completable,
                total_if_replaced=round(total_con_reemplazos, 2) if completable else None,
                replacements=reemplazos,
            )
        )

    # Primero las que se pueden completar (con menos reemplazos y más baratas), luego
    # las demás por cuántos productos ya tienen.
    opciones.sort(
        key=lambda o: (
            not o.completable,
            len(o.replacements) if o.completable else -o.items_priced,
            o.total_if_replaced if o.completable else 0,
        )
    )
    return SingleStoreResponse(list_id=list_id, options=opciones)
