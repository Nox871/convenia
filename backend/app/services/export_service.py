"""Exportación de datos para administradores."""
from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.engine import Connection

from app.core.category_bucket import categoria_de_producto
from app.core.csv_export import BOM, HEADERS, encode_csv, format_row
from app.core.database import engine
from app.core.exceptions import InvalidParameterError, NotFoundError

# Tope de filas por exportación: un historial completo de meses puede ser de
# millones de filas, demasiado para bajarlo a un teléfono. Se avisa en vez de
# mandar un archivo enorme o cortarlo en silencio.
MAX_ROWS = 300_000
_CHUNK = 2000


def _filters(supermarket_code: str | None, days: int) -> tuple[str, dict]:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    params: dict = {"since": since}
    clause = "po.observed_at >= :since"
    if supermarket_code:
        clause += " AND s.code = :code"
        params["code"] = supermarket_code
    return clause, params


def prepare_price_history_export(
    conn: Connection, supermarket_code: str | None, days: int
) -> tuple[str | None, int]:
    """Valida los filtros y cuenta las filas; devuelve (código normalizado, filas)."""
    code = supermarket_code.strip().upper() if supermarket_code else None
    if code and conn.execute(text("SELECT 1 FROM supermarkets WHERE code = :c"), {"c": code}).first() is None:
        raise NotFoundError(f"Supermercado '{supermarket_code}' no existe")

    clause, params = _filters(code, days)
    total = conn.execute(
        text(
            f"""
            SELECT COUNT(*)
            FROM price_observations po
            JOIN source_products sp ON sp.id = po.source_product_id
            JOIN supermarkets s ON s.id = sp.supermarket_id
            WHERE {clause}
            """
        ),
        params,
    ).scalar_one()

    if total > MAX_ROWS:
        raise InvalidParameterError(
            f"El historial pedido tiene {total:,} registros y el máximo por exportación es {MAX_ROWS:,}. "
            "Elige un supermercado o un periodo más corto."
        )
    return code, total


def iter_price_history_csv(supermarket_code: str | None, days: int) -> Iterator[bytes]:
    """Genera el CSV por bloques. Abre su PROPIA conexión: la del request ya
    puede estar cerrada cuando se empieza a enviar el cuerpo."""
    clause, params = _filters(supermarket_code, days)
    yield (BOM + encode_csv([HEADERS])).encode("utf-8")

    with engine.connect() as conn:
        result = conn.execution_options(stream_results=True, yield_per=_CHUNK).execute(
            text(
                f"""
                SELECT po.observed_at, s.code AS supermarket_code, s.name AS supermarket_name,
                       sp.name_raw AS name, sp.brand_raw AS brand, sc.name_raw AS category_path,
                       po.price, po.list_price, po.currency, po.available,
                       sp.id AS source_product_id, sp.product_url
                FROM price_observations po
                JOIN source_products sp ON sp.id = po.source_product_id
                JOIN supermarkets s ON s.id = sp.supermarket_id
                LEFT JOIN source_categories sc ON sc.id = sp.source_category_id
                WHERE {clause}
                ORDER BY po.observed_at, s.code, sp.id
                """
            ),
            params,
        )
        for chunk in result.mappings().partitions():
            rows = [
                format_row(row, categoria_de_producto(row["name"], row["category_path"]))
                for row in chunk
            ]
            yield encode_csv(rows).encode("utf-8")
