"""Acceso a datos de precios (price_observations)."""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection


def get_latest_offers(
    conn: Connection, source_product_ids: list[int], supermarket_codes: list[str] | None = None
) -> list[dict]:
    """Última observación de precio DISPONIBLE por cada source_product dado.

    Usa `available = TRUE` explícitamente (regla de negocio: nunca comparar u
    ofrecer precios marcados como no disponibles) y ordena por precio
    ascendente para que el más barato quede primero.
    """
    if not source_product_ids:
        return []

    scope = "" if supermarket_codes is None else "AND s.code = ANY(:sm_codes)"
    rows = conn.execute(
        text(
            f"""
            SELECT
                s.code AS supermarket_code,
                s.name AS supermarket_name,
                po.price,
                po.list_price,
                po.currency,
                po.available,
                po.observed_at,
                po.payment_methods
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            JOIN LATERAL (
                SELECT price, list_price, currency, available, observed_at, payment_methods
                FROM price_observations
                WHERE source_product_id = sp.id AND available = TRUE
                ORDER BY observed_at DESC
                LIMIT 1
            ) po ON TRUE
            WHERE sp.id = ANY(:ids) {scope}
            ORDER BY po.price ASC
            """
        ),
        {"ids": source_product_ids, "sm_codes": supermarket_codes},
    ).mappings().all()

    return [dict(row) for row in rows]


def get_offers_for_compare(
    conn: Connection, source_product_ids: list[int], supermarket_codes: list[str] | None = None
) -> list[dict]:
    """Una fila por CADA supermercado activo (la arquitectura no asume una
    cantidad fija de fuentes), con los campos de precio en NULL cuando ese
    supermercado no tiene oferta para este producto -- nunca se omite la
    fila ni se usa precio 0.

    Defensivo: `source_product_ids` en teoría trae como mucho un id por
    supermercado para un mismo producto canónico, pero si la homologación
    upstream llegara a asociar más de uno del mismo supermercado (unión
    transitiva vía un tercer supermercado), esta consulta igual devuelve
    UNA sola fila por supermercado -- se queda con el que tenga la
    observación de precio disponible más reciente."""
    scope = "" if supermarket_codes is None else "AND s.code = ANY(:sm_codes)"
    rows = conn.execute(
        text(
            f"""
            SELECT
                s.code AS supermarket_code,
                s.name AS supermarket_name,
                elegido.price,
                elegido.list_price,
                elegido.currency,
                elegido.available,
                elegido.observed_at,
                elegido.payment_methods
            FROM supermarkets s
            LEFT JOIN LATERAL (
                SELECT po.price, po.list_price, po.currency, po.available,
                       po.observed_at, po.payment_methods
                FROM source_products sp
                LEFT JOIN LATERAL (
                    SELECT price, list_price, currency, available, observed_at, payment_methods
                    FROM price_observations
                    WHERE source_product_id = sp.id AND available = TRUE
                    ORDER BY observed_at DESC
                    LIMIT 1
                ) po ON TRUE
                WHERE sp.supermarket_id = s.id AND sp.id = ANY(:ids)
                ORDER BY (po.observed_at IS NOT NULL) DESC, po.observed_at DESC
                LIMIT 1
            ) elegido ON TRUE
            WHERE s.is_active = TRUE {scope}
            ORDER BY s.name ASC
            """
        ),
        {"ids": source_product_ids or [], "sm_codes": supermarket_codes},
    ).mappings().all()

    return [dict(row) for row in rows]


def get_price_history_summary(conn: Connection, source_product_ids: list[int]) -> dict | None:
    """Agregados (min/max/avg/actual/variación) calculados en SQL — nunca
    trayendo todas las observaciones a Python para calcularlos ahí."""
    if not source_product_ids:
        return None

    row = conn.execute(
        text(
            """
            SELECT
                MIN(price) AS min_price,
                MAX(price) AS max_price,
                AVG(price) AS avg_price,
                COUNT(*) AS observations_count
            FROM price_observations
            WHERE source_product_id = ANY(:ids)
            """
        ),
        {"ids": source_product_ids},
    ).mappings().first()

    if row is None or row["observations_count"] == 0:
        return None

    actual_row = conn.execute(
        text(
            """
            SELECT price, observed_at
            FROM price_observations
            WHERE source_product_id = ANY(:ids)
            ORDER BY observed_at DESC
            LIMIT 1
            """
        ),
        {"ids": source_product_ids},
    ).mappings().first()

    primera_row = conn.execute(
        text(
            """
            SELECT price
            FROM price_observations
            WHERE source_product_id = ANY(:ids)
            ORDER BY observed_at ASC
            LIMIT 1
            """
        ),
        {"ids": source_product_ids},
    ).mappings().first()

    resultado = dict(row)
    resultado["current_price"] = actual_row["price"]
    resultado["current_observed_at"] = actual_row["observed_at"]
    resultado["first_price"] = primera_row["price"]
    return resultado


def get_price_history_observations(
    conn: Connection,
    source_product_ids: list[int],
    offset: int,
    limit: int,
    month: str | None = None,
) -> tuple[list[dict], int]:
    """Lista paginada de observaciones históricas (nunca todo el historial
    de una vez). `month` (formato 'YYYY-MM') filtra a un mes específico
    para el drill-down del historial visual."""
    if not source_product_ids:
        return [], 0

    params: dict = {"ids": source_product_ids, "offset": offset, "limit": limit}
    # Filtro de mes calculado en SQL (no en Python) para no depender de saber
    # cuántos días tiene el mes -- `desde::date + interval '1 month'`.
    filtro_mes = ""
    if month:
        params["desde"] = f"{month}-01"
        filtro_mes = (
            "AND observed_at >= CAST(:desde AS date) "
            "AND observed_at < (CAST(:desde AS date) + interval '1 month')"
        )

    rows = conn.execute(
        text(
            f"""
            SELECT price, list_price, currency, available, observed_at
            FROM price_observations
            WHERE source_product_id = ANY(:ids)
            {filtro_mes}
            ORDER BY observed_at DESC
            OFFSET :offset LIMIT :limit
            """
        ),
        params,
    ).mappings().all()

    total = conn.execute(
        text(
            f"""
            SELECT COUNT(*) FROM price_observations
            WHERE source_product_id = ANY(:ids)
            {filtro_mes}
            """
        ),
        {k: v for k, v in params.items() if k not in ("offset", "limit")},
    ).scalar_one()

    return [dict(row) for row in rows], total


def get_price_history_monthly(conn: Connection, source_product_ids: list[int]) -> list[dict]:
    """Agregados por mes (min/max/avg/cantidad) para el historial visual de
    barras. Meses sin observaciones simplemente no aparecen en el
    resultado -- nunca se rellenan con 0."""
    if not source_product_ids:
        return []

    rows = conn.execute(
        text(
            """
            SELECT
                to_char(date_trunc('month', observed_at), 'YYYY-MM') AS month,
                MIN(price) AS min_price,
                MAX(price) AS max_price,
                AVG(price) AS avg_price,
                COUNT(*) AS observations_count
            FROM price_observations
            WHERE source_product_id = ANY(:ids)
            GROUP BY 1
            ORDER BY 1 ASC
            """
        ),
        {"ids": source_product_ids},
    ).mappings().all()

    return [dict(row) for row in rows]


def list_current_offers(conn: Connection, supermarket_codes: list[str] | None = None) -> list[dict]:
    """Una fila por producto activo con su precio disponible más reciente, para
    buscar sustitutos más baratos. Se limita a los supermercados al alcance."""
    scope = "" if supermarket_codes is None else "AND s.code = ANY(:sm_codes)"
    rows = conn.execute(
        text(
            f"""
            SELECT
                sp.id AS source_product_id,
                sp.name_raw AS name,
                sp.brand_raw AS brand,
                sp.image_url,
                po.price::float AS price,
                s.code AS supermarket_code,
                s.name AS supermarket_name
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            JOIN LATERAL (
                SELECT price FROM price_observations
                WHERE source_product_id = sp.id AND available = TRUE
                ORDER BY observed_at DESC LIMIT 1
            ) po ON TRUE
            WHERE sp.is_active = TRUE AND s.is_active = TRUE {scope}
            """
        ),
        {"sm_codes": supermarket_codes},
    ).mappings().all()
    return [dict(row) for row in rows]
