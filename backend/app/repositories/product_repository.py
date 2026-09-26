"""Acceso a datos de productos."""
from __future__ import annotations


from sqlalchemy import text
from sqlalchemy.engine import Connection

from app.core.category_bucket import categoria_de_producto
from app.core.scope import sql_scope_clause
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
    category_source_ids: list[int] | None = None,
    supermarket_codes: list[str] | None = None,
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
    params: dict = {"offset": offset, "limit": limit, "sm_codes": supermarket_codes}
    sm_best, sm_cnt, sm_sp = (
        sql_scope_clause("sp", supermarket_codes),
        sql_scope_clause("sp2", supermarket_codes),
        sql_scope_clause("sp", supermarket_codes),
    )

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

    # Filtro por categoría: recibe los ids de los productos de supermercado
    # que `category_service` clasificó en la etiqueta pedida (por nombre de
    # producto, con el pasillo como respaldo), la misma clasificación que
    # cuenta `/categories`.
    canon_category_exists = ""
    suelto_category_join = ""
    suelto_category_filter = ""
    if category_source_ids is not None:
        params["category_source_ids"] = category_source_ids
        canon_category_exists = """
            AND EXISTS (
                SELECT 1 FROM product_matches pm4
                JOIN source_products sp4 ON sp4.id = pm4.source_product_id
                WHERE pm4.product_id = p.id AND pm4.status = 'CONFIRMED'
                  AND sp4.id = ANY(:category_source_ids)
            )
        """
        suelto_category_join = ""
        suelto_category_filter = "AND sp.id = ANY(:category_source_ids)"

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
                    WHERE pm.product_id = p.id AND pm.status = 'CONFIRMED' {sm_best}
                    ORDER BY po.price ASC
                    LIMIT 1
                ) best ON TRUE
                JOIN LATERAL (
                    SELECT COUNT(DISTINCT sp2.supermarket_id) AS offers_count
                    FROM product_matches pm2
                    JOIN source_products sp2 ON sp2.id = pm2.source_product_id
                    WHERE pm2.product_id = p.id AND pm2.status = 'CONFIRMED' {sm_cnt}
                      AND EXISTS (
                          SELECT 1 FROM price_observations po3
                          WHERE po3.source_product_id = sp2.id AND po3.available = TRUE
                      )
                ) cnt ON TRUE
                WHERE TRUE {canon_extra_q} {canon_supermarket_exists} {canon_category_exists}
            ),
            sueltos AS (
                SELECT
                    sp.id AS source_product_id, sp.name_raw AS name, sp.brand_raw AS brand,
                    sp.image_url, lp.price, lp.list_price, lp.currency, lp.observed_at,
                    1 AS offers_count, s.code AS supermarket_code, s.name AS supermarket_name
                FROM source_products sp
                JOIN supermarkets s ON s.id = sp.supermarket_id
                LEFT JOIN product_matches pm ON pm.source_product_id = sp.id AND pm.status = 'CONFIRMED'
                {suelto_category_join}
                LEFT JOIN LATERAL (
                    SELECT price, list_price, currency, observed_at
                    FROM price_observations
                    WHERE source_product_id = sp.id AND available = TRUE
                    ORDER BY observed_at DESC
                    LIMIT 1
                ) lp ON TRUE
                WHERE {suelto_where} {suelto_extra_q} {suelto_category_filter} {sm_sp}
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
        "category": categoria_de_producto(row["name_raw"], row["category_name"]),
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

    # Un producto homologado no tiene foto propia: se usa la de su mejor
    # oferta que tenga imagen (primero las que tienen foto, luego menor precio).
    image = conn.execute(
        text(
            """
            SELECT sp.image_url
            FROM product_matches pm
            JOIN source_products sp ON sp.id = pm.source_product_id
            LEFT JOIN LATERAL (
                SELECT price FROM price_observations
                WHERE source_product_id = sp.id AND available = TRUE
                ORDER BY observed_at DESC LIMIT 1
            ) po ON TRUE
            WHERE pm.product_id = :id AND pm.status = 'CONFIRMED'
              AND sp.image_url IS NOT NULL AND sp.image_url <> ''
            ORDER BY po.price ASC NULLS LAST
            LIMIT 1
            """
        ),
        {"id": product_id},
    ).scalar()

    return {
        "id": f"p-{product['id']}",
        "name": product["name"],
        "brand": product["brand"],
        "category": categoria_de_producto(product["name"], product["category"]),
        "image_url": image,
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


def search_products_fuzzy(
    conn: Connection,
    q: str,
    limit: int,
    prefer: str = "comparable",
    supermarket_codes: list[str] | None = None,
) -> list[dict]:
    """Productos cuyo nombre se PARECE a `q`, para cuando el texto no es
    exacto (entrada por voz, texto extraído por OCR, o errores de tipeo) o
    es genérico ("arroz", "leche").

    Compara palabra por palabra usando distancia de edición (Levenshtein),
    no el nombre completo de una sola vez: "aroz" tiene una similitud baja
    contra "Arroz Diana 500 G" completo (por la marca y la cantidad), pero
    muy alta contra la palabra "Arroz" sola. Cada palabra del texto
    buscado debe tener una palabra parecida en el nombre del producto
    (`MIN` de los mejores puntajes por palabra). `unaccent` evita que una
    tilde parta una palabra en dos al compararla.

    Orden (lo que decide cuál se propone primero cuando el texto es
    genérico y muchos productos empatan en similitud):
      1. Nombres que EMPIEZAN con lo pedido antes que los que solo lo
         mencionan de pasada ("Sal REFISAL" antes que "Mantequilla sin sal").
      2. Similitud (redondeada a 1 decimal, para que un empate práctico no
         se rompa por centésimas).
      3. `prefer='comparable'` (defecto): más supermercados que lo venden
         primero -- es el único criterio que permite comparar de verdad --
         y luego menor precio. `prefer='price'`: menor precio primero.
    Sólo se devuelven productos con al menos un precio disponible. Nunca se
    agrega uno automáticamente: el usuario confirma en la pantalla de
    revisión.
    """
    if prefer == "price":
        order_by = "tier ASC, ROUND(score::numeric, 1) DESC, price ASC, offers_count DESC, name ASC"
    else:
        order_by = "tier ASC, ROUND(score::numeric, 1) DESC, offers_count DESC, price ASC, name ASC"

    sm_best, sm_cnt, sm_sp = (
        sql_scope_clause("sp", supermarket_codes),
        sql_scope_clause("sp2", supermarket_codes),
        sql_scope_clause("sp", supermarket_codes),
    )
    rows = conn.execute(
        text(
            f"""
            WITH query_words AS (
                SELECT word
                FROM unnest(regexp_split_to_array(lower(unaccent(:q)), '[^a-z0-9]+')) AS word
                WHERE length(word) > 1
            ),
            candidatos AS (
                SELECT 'p-' || p.id AS id, p.name, p.brand,
                       best.image_url, best.price, cnt.offers_count
                FROM products p
                JOIN LATERAL (
                    SELECT sp.image_url, po.price
                    FROM product_matches pm
                    JOIN source_products sp ON sp.id = pm.source_product_id
                    JOIN LATERAL (
                        SELECT price FROM price_observations
                        WHERE source_product_id = sp.id AND available = TRUE
                        ORDER BY observed_at DESC LIMIT 1
                    ) po ON TRUE
                    WHERE pm.product_id = p.id AND pm.status = 'CONFIRMED' {sm_best}
                    ORDER BY po.price ASC
                    LIMIT 1
                ) best ON TRUE
                JOIN LATERAL (
                    SELECT COUNT(DISTINCT sp2.supermarket_id) AS offers_count
                    FROM product_matches pm2
                    JOIN source_products sp2 ON sp2.id = pm2.source_product_id
                    WHERE pm2.product_id = p.id AND pm2.status = 'CONFIRMED' {sm_cnt}
                      AND EXISTS (
                          SELECT 1 FROM price_observations po3
                          WHERE po3.source_product_id = sp2.id AND po3.available = TRUE
                      )
                ) cnt ON TRUE

                UNION ALL

                SELECT 'sp-' || sp.id AS id, sp.name_raw AS name, sp.brand_raw AS brand,
                       sp.image_url, lp.price, 1 AS offers_count
                FROM source_products sp
                JOIN LATERAL (
                    SELECT price FROM price_observations
                    WHERE source_product_id = sp.id AND available = TRUE
                    ORDER BY observed_at DESC LIMIT 1
                ) lp ON TRUE
                WHERE sp.is_active = TRUE {sm_sp}
                  AND NOT EXISTS (
                      SELECT 1 FROM product_matches pm
                      WHERE pm.source_product_id = sp.id AND pm.status = 'CONFIRMED'
                  )
            ),
            candidate_words AS (
                SELECT c.id, word AS cword, pos
                FROM candidatos c,
                     unnest(regexp_split_to_array(lower(unaccent(c.name)), '[^a-z0-9]+'))
                         WITH ORDINALITY AS t(word, pos)
                WHERE length(word) > 1
            ),
            puntajes_por_palabra AS (
                SELECT cw.id, qw.word AS qword,
                       MAX(
                           1.0 - levenshtein(qw.word, cw.cword)::float
                               / GREATEST(length(qw.word), length(cw.cword))
                       ) AS best_score
                FROM query_words qw
                JOIN candidate_words cw ON true
                GROUP BY cw.id, qw.word
            ),
            puntaje AS (
                SELECT id, MIN(best_score) AS score
                FROM puntajes_por_palabra
                GROUP BY id
                HAVING MIN(best_score) >= 0.55
            ),
            primera_palabra AS (
                SELECT cw.id,
                       MAX(
                           1.0 - levenshtein(qw.word, cw.cword)::float
                               / GREATEST(length(qw.word), length(cw.cword))
                       ) AS first_sim
                FROM query_words qw
                JOIN candidate_words cw ON cw.pos = 1
                GROUP BY cw.id
            )
            SELECT c.id, c.name, c.brand, c.image_url,
                   c.price::float AS price, c.offers_count::int AS offers_count,
                   pu.score,
                   CASE WHEN pp.first_sim >= 0.8 THEN 0 ELSE 1 END AS tier
            FROM puntaje pu
            JOIN candidatos c ON c.id = pu.id
            LEFT JOIN primera_palabra pp ON pp.id = pu.id
            ORDER BY {order_by}
            LIMIT :limit
            """
        ),
        {"q": q, "limit": limit, "sm_codes": supermarket_codes},
    ).mappings().all()
    return [dict(row) for row in rows]
