from __future__ import annotations

import time
from collections import defaultdict

from sqlalchemy.engine import Connection

from app.core.category_bucket import categoria_de_producto
from app.repositories import category_repository
from app.schemas.category import Category, CategoryListResponse


# Los productos sólo cambian cuando corre el ETL (una vez al día), así que la
# clasificación se guarda en memoria unos minutos en lugar de recalcularla
# en cada pantalla que la pide.
_CACHE_SECONDS = 300
_cache: tuple[float, list[tuple[dict, str]]] | None = None


def _clasificar(conn: Connection) -> list[tuple[dict, str]]:
    global _cache
    if _cache is not None and time.monotonic() - _cache[0] < _CACHE_SECONDS:
        return _cache[1]
    clasificados = _clasificar_sin_cache(conn)
    _cache = (time.monotonic(), clasificados)
    return clasificados


def _clasificar_sin_cache(conn: Connection) -> list[tuple[dict, str]]:
    """(producto, etiqueta amigable) de cada producto activo que pertenece
    al alcance de la canasta. La categoría sale del nombre del producto y,
    sólo si el nombre no alcanza, del pasillo del supermercado."""
    clasificados = []
    for fila in category_repository.list_active_products_with_category(conn):
        etiqueta = categoria_de_producto(fila["name"], fila["category_path"])
        if etiqueta is not None:
            clasificados.append((fila, etiqueta))
    return clasificados


def source_product_ids_for_label(conn: Connection, label: str) -> list[int]:
    """Ids de los productos de supermercado que caen en `label`. Es la misma
    clasificación que usa `list_categories`, así el conteo de la tarjeta y
    la lista que se abre al tocarla no pueden discrepar."""
    return [fila["id"] for fila, etiqueta in _clasificar(conn) if etiqueta == label]


def list_categories(conn: Connection) -> CategoryListResponse:
    productos_por_etiqueta: dict[str, int] = defaultdict(int)
    supermercados_por_etiqueta: dict[str, set[str]] = defaultdict(set)

    for fila, etiqueta in _clasificar(conn):
        productos_por_etiqueta[etiqueta] += 1
        supermercados_por_etiqueta[etiqueta].add(fila["supermarket_code"])

    items = [
        Category(
            label=etiqueta,
            products_count=productos_por_etiqueta[etiqueta],
            supermarkets=sorted(supermercados_por_etiqueta[etiqueta]),
        )
        for etiqueta in sorted(productos_por_etiqueta)
    ]
    return CategoryListResponse(items=items)
