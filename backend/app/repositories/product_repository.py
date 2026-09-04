"""Acceso a datos de productos.

FASE ACTUAL: `products` y `product_matches` están vacías (no se ha corrido la
homologación), así que el listado y el detalle se resuelven directamente
contra `source_products`. Cada función deja explícito qué pasará cuando exista
homologación, para que el cambio sea local a este archivo y no toque
services/routers/schemas.
"""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection

from app.core.product_ref import ProductRef, encode_source_ref


def search_source_products(
    conn: Connection,
    q: str | None,
    supermarket_code: str | None,
    offset: int,
    limit: int,
) -> tuple[list[dict], int]:
    """Búsqueda paginada de productos.

    FASE 1 (actual): un resultado por `source_product` (sin agrupar entre
    supermercados, porque todavía no hay `product_matches` confirmados).

    FASE 2 (futura, cuando haya homologación): esta función deberá primero
    agrupar por `products.id` a través de `product_matches` con
    status='CONFIRMED', devolviendo un resultado por producto canónico con
    su mejor precio entre supermercados, y sólo usar `source_products` sueltos
    como fallback para lo que aún no esté homologado. El contrato de salida
    (lista de dicts con las mismas llaves) no cambia.
    """
    filters = ["sp.is_active = TRUE"]
    params: dict = {"offset": offset, "limit": limit}

    if q:
        filters.append("sp.name_raw ILIKE :q_pattern")
        params["q_pattern"] = f"%{q}%"

    if supermarket_code:
        filters.append("s.code = :supermarket_code")
        params["supermarket_code"] = supermarket_code

    where_clause = " AND ".join(filters)

    rows = conn.execute(
        text(
            f"""
            SELECT
                sp.id AS source_product_id,
                sp.name_raw,
                sp.brand_raw,
                sp.image_url,
                s.code AS supermarket_code,
                s.name AS supermarket_name,
                lp.price,
                lp.list_price,
                lp.currency
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            LEFT JOIN LATERAL (
                SELECT price, list_price, currency
                FROM price_observations po
                WHERE po.source_product_id = sp.id AND po.available = TRUE
                ORDER BY po.observed_at DESC
                LIMIT 1
            ) lp ON TRUE
            WHERE {where_clause}
            ORDER BY sp.name_raw ASC, sp.id ASC
            OFFSET :offset LIMIT :limit
            """
        ),
        params,
    ).mappings().all()

    total = conn.execute(
        text(
            f"""
            SELECT COUNT(*)
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            WHERE {where_clause}
            """
        ),
        {k: v for k, v in params.items() if k not in ("offset", "limit")},
    ).scalar_one()

    items = [
        {
            "id": encode_source_ref(row["source_product_id"]),
            "name": row["name_raw"],
            "brand": row["brand_raw"],
            "image_url": row["image_url"],
            "supermarket_code": row["supermarket_code"],
            "supermarket_name": row["supermarket_name"],
            "price": float(row["price"]) if row["price"] is not None else None,
            "list_price": float(row["list_price"]) if row["list_price"] is not None else None,
            "currency": row["currency"],
            "is_matched": False,
        }
        for row in rows
    ]

    return items, total


def get_source_product_detail(conn: Connection, source_product_id: int) -> dict | None:
    row = conn.execute(
        text(
            """
            SELECT
                sp.id, sp.name_raw, sp.brand_raw, sp.image_url, sp.product_url,
                sc.name_raw AS category_name,
                s.code AS supermarket_code
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            LEFT JOIN source_categories sc ON sc.id = sp.source_category_id
            WHERE sp.id = :id
            """
        ),
        {"id": source_product_id},
    ).mappings().first()

    if row is None:
        return None

    return {
        "id": encode_source_ref(row["id"]),
        "name": row["name_raw"],
        "brand": row["brand_raw"],
        "category": row["category_name"],
        "image_url": row["image_url"],
        "product_url": row["product_url"],
        "is_matched": False,
        "offers_count": 1,
        "supermarkets": [row["supermarket_code"]],
    }


def get_canonical_product_detail(conn: Connection, product_id: int) -> dict | None:
    """Detalle de un producto ya homologado (products + product_matches).

    Hoy `products` está vacía, así que esta función siempre devolverá None en
    la práctica, pero queda lista para cuando exista homologación: el
    endpoint no necesita cambiar, sólo empezará a recibir ids con prefijo
    'p-' una vez que el proceso de matching los genere.
    """
    product = conn.execute(
        text("SELECT id, name, brand, category FROM products WHERE id = :id"),
        {"id": product_id},
    ).mappings().first()

    if product is None:
        return None

    matches = conn.execute(
        text(
            """
            SELECT s.code AS supermarket_code
            FROM product_matches pm
            JOIN source_products sp ON sp.id = pm.source_product_id
            JOIN supermarkets s ON s.id = sp.supermarket_id
            WHERE pm.product_id = :id AND pm.status = 'CONFIRMED'
            """
        ),
        {"id": product_id},
    ).mappings().all()

    supermarket_codes = [m["supermarket_code"] for m in matches]

    return {
        "id": f"p-{product['id']}",
        "name": product["name"],
        "brand": product["brand"],
        "category": product["category"],
        "image_url": None,
        "product_url": None,
        "is_matched": True,
        "offers_count": len(supermarket_codes),
        "supermarkets": supermarket_codes,
    }


def resolve_source_product_ids(conn: Connection, ref: ProductRef) -> list[int]:
    """Dado un id opaco de producto, devuelve los `source_products.id` que lo respaldan.

    - 'sp-<id>': el propio source_product.
    - 'p-<id>': todos los source_products con match CONFIRMED hacia ese producto canónico.
    """
    if ref.kind == "source":
        return [ref.numeric_id]

    rows = conn.execute(
        text(
            """
            SELECT source_product_id
            FROM product_matches
            WHERE product_id = :product_id AND status = 'CONFIRMED'
            """
        ),
        {"product_id": ref.numeric_id},
    ).all()
    return [row[0] for row in rows]
