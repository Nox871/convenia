"""Acceso a datos de productos."""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection

from app.core.category_bucket import etiqueta_amigable
from app.core.product_ref import ProductRef, encode_source_ref


def search_source_products(
    conn: Connection,
    q: str | None,
    supermarket_code: str | None,
    offset: int,
    limit: int,
) -> tuple[list[dict], int]:
    """Búsqueda paginada de productos: un resultado por `source_product`,
    sin agrupar entre supermercados.

    No la usa ningún router actualmente; el listado de productos usa
    `search_products_grouped`, que sí agrupa por producto canónico cuando
    hay homologación confirmada. Se mantiene por si hace falta una
    búsqueda sin agrupar más adelante.
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


def search_products_grouped(
    conn: Connection,
    q: str | None,
    supermarket_code: str | None,
    sort: str,
    offset: int,
    limit: int,
) -> tuple[list[dict], int]:
    """Búsqueda paginada que agrupa por producto canónico cuando hay
    homologación confirmada; los productos sin match confirmado se listan
    sueltos (nunca se ocultan, sólo no se agrupan porque no hay evidencia
    de equivalencia).

    `sort`: 'price' (mejor precio ascendente, default) o 'recent' (última
    observación de precio más reciente primero).
    """
    canon_filters = ["pm.status = 'CONFIRMED'"]
    suelto_filters = ["pm.id IS NULL", "sp.is_active = TRUE"]
    params: dict = {"offset": offset, "limit": limit}

    if q:
        params["q_pattern"] = f"%{q}%"
        canon_extra_q = "AND p.name ILIKE :q_pattern"
        suelto_extra_q = "AND sp.name_raw ILIKE :q_pattern"
    else:
        canon_extra_q = ""
        suelto_extra_q = ""

    if supermarket_code:
        params["supermarket_code"] = supermarket_code
        canon_supermarket_exists = """
            AND EXISTS (
                SELECT 1 FROM product_matches pm3
                JOIN source_products sp3 ON sp3.id = pm3.source_product_id
                JOIN supermarkets s3 ON s3.id = sp3.supermarket_id
                WHERE pm3.product_id = p.id AND pm3.status = 'CONFIRMED'
                  AND s3.code = :supermarket_code
            )
        """
        suelto_filters.append("s.code = :supermarket_code")
    else:
        canon_supermarket_exists = ""

    order_by = "observed_at DESC NULLS LAST" if sort == "recent" else "price IS NULL, price ASC"

    suelto_where = " AND ".join(suelto_filters)

    rows = conn.execute(
        text(
            f"""
            WITH canonicos AS (
                SELECT
                    p.id AS product_id, p.name, p.brand,
                    best.image_url, best.price, best.list_price, best.currency, best.observed_at,
                    cnt.offers_count
                FROM products p
                JOIN LATERAL (
                    SELECT sp.image_url, po.price, po.list_price, po.currency, po.observed_at
                    FROM product_matches pm
                    JOIN source_products sp ON sp.id = pm.source_product_id
                    JOIN LATERAL (
                        SELECT price, list_price, currency, observed_at
                        FROM price_observations
                        WHERE source_product_id = sp.id AND available = TRUE
                        ORDER BY observed_at DESC
                        LIMIT 1
                    ) po ON TRUE
                    WHERE pm.product_id = p.id AND pm.status = 'CONFIRMED'
                    ORDER BY po.price ASC
                    LIMIT 1
                ) best ON TRUE
                JOIN LATERAL (
                    SELECT COUNT(DISTINCT sp2.supermarket_id) AS offers_count
                    FROM product_matches pm2
                    JOIN source_products sp2 ON sp2.id = pm2.source_product_id
                    WHERE pm2.product_id = p.id AND pm2.status = 'CONFIRMED'
                      AND EXISTS (
                          SELECT 1 FROM price_observations po3
                          WHERE po3.source_product_id = sp2.id AND po3.available = TRUE
                      )
                ) cnt ON TRUE
                WHERE TRUE {canon_extra_q} {canon_supermarket_exists}
            ),
            sueltos AS (
                SELECT
                    sp.id AS source_product_id, sp.name_raw AS name, sp.brand_raw AS brand,
                    sp.image_url, lp.price, lp.list_price, lp.currency, lp.observed_at,
                    1 AS offers_count, s.code AS supermarket_code, s.name AS supermarket_name
                FROM source_products sp
                JOIN supermarkets s ON s.id = sp.supermarket_id
                LEFT JOIN product_matches pm ON pm.source_product_id = sp.id AND pm.status = 'CONFIRMED'
                LEFT JOIN LATERAL (
                    SELECT price, list_price, currency, observed_at
                    FROM price_observations
                    WHERE source_product_id = sp.id AND available = TRUE
                    ORDER BY observed_at DESC
                    LIMIT 1
                ) lp ON TRUE
                WHERE {suelto_where} {suelto_extra_q}
            ),
            combinado AS (
                SELECT 'p-' || product_id::text AS id, name, brand, image_url,
                       price, list_price, currency, observed_at, offers_count,
                       NULL::text AS supermarket_code, NULL::text AS supermarket_name
                FROM canonicos
                UNION ALL
                SELECT 'sp-' || source_product_id::text, name, brand, image_url,
                       price, list_price, currency, observed_at, offers_count,
                       supermarket_code, supermarket_name
                FROM sueltos
            )
            SELECT *, COUNT(*) OVER() AS full_count
            FROM combinado
            ORDER BY {order_by}, name ASC
            OFFSET :offset LIMIT :limit
            """
        ),
        params,
    ).mappings().all()

    total = rows[0]["full_count"] if rows else 0

    items = [
        {
            "id": row["id"],
            "name": row["name"],
            "brand": row["brand"],
            "image_url": row["image_url"],
            "supermarket_code": row["supermarket_code"],
            "supermarket_name": row["supermarket_name"],
            "price": float(row["price"]) if row["price"] is not None else None,
            "list_price": float(row["list_price"]) if row["list_price"] is not None else None,
            "currency": row["currency"],
            "offers_count": row["offers_count"],
            "is_matched": row["id"].startswith("p-"),
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
        # Etiqueta amigable ("Frutas y verduras"), nunca la ruta cruda
        # (source_categories.name_raw, ej. "/Despensa/Granos/Arroz/") -- si
        # no hay bucket reconocible, se omite en vez de mostrar algo técnico.
        "category": etiqueta_amigable(row["category_name"]),
        "image_url": row["image_url"],
        "product_url": row["product_url"],
        "is_matched": False,
        "offers_count": 1,
        "supermarkets": [row["supermarket_code"]],
    }


def get_canonical_product_detail(conn: Connection, product_id: int) -> dict | None:
    """Detalle de un producto ya homologado (products + product_matches)."""
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
        "category": etiqueta_amigable(product["category"]),
        "image_url": None,
        "product_url": None,
        "is_matched": True,
        "offers_count": len(supermarket_codes),
        "supermarkets": supermarket_codes,
    }


def get_canonical_quantity_unit(conn: Connection, product_id: int) -> dict | None:
    """`quantity`/`unit` del producto canónico, para calcular precio unitario.
    Sólo existe cuando el ancla de homologación pudo extraer una cantidad
    reconocible del nombre -- si es None, el precio unitario simplemente
    no se calcula (nunca se inventa)."""
    row = conn.execute(
        text("SELECT quantity, unit FROM products WHERE id = :id"),
        {"id": product_id},
    ).mappings().first()
    if row is None or row["quantity"] is None or row["unit"] is None:
        return None
    return dict(row)


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
