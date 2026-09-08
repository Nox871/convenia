from __future__ import annotations

from collections import defaultdict

from sqlalchemy.engine import Connection

from app.core.category_bucket import obtener_bucket
from app.repositories import category_repository
from app.schemas.category import Category, CategoryListResponse


def list_categories(conn: Connection) -> CategoryListResponse:
    filas = category_repository.list_categories_raw(conn)

    productos_por_bucket: dict[str, int] = defaultdict(int)
    supermercados_por_bucket: dict[str, set[str]] = defaultdict(set)

    for fila in filas:
        bucket = obtener_bucket(fila["name_raw"])
        if bucket is None:
            continue
        productos_por_bucket[bucket] += fila["active_products_count"]
        supermercados_por_bucket[bucket].add(fila["supermarket_code"])

    items = [
        Category(
            bucket=bucket,
            products_count=productos_por_bucket[bucket],
            supermarkets=sorted(supermercados_por_bucket[bucket]),
        )
        for bucket in sorted(productos_por_bucket)
    ]
    return CategoryListResponse(items=items)
