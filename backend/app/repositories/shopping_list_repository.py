"""Acceso a datos de listas de compra (shopping_lists/shopping_list_items).

Sin sistema de autenticación en el proyecto: `owner_ref` es un identificador
de dispositivo que la app móvil genera y persiste localmente (ver migración
`005_shopping_lists.sql`), no un usuario real. Cada operación exige el
`owner_ref` correcto para no dejar las listas globalmente visibles.

Nota de transacciones: el motor del backend usa SQLAlchemy 2.0 "future"
(`backend/app/core/database.py`), que auto-inicia una transacción implícita
en el primer `execute()` de la conexión. Como una misma request suele
encadenar varias llamadas a este módulo sobre la MISMA conexión (verificar
dueño -> escribir -> leer detalle actualizado), cada función de escritura
hace su propio `conn.commit()` tras ejecutar -- nunca `conn.begin()`, que
fallaría si la conexión ya tiene una transacción autoiniciada por una
llamada anterior en la misma request.
"""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection


def create_list(conn: Connection, owner_ref: str, name: str) -> int:
    row = conn.execute(
        text(
            "INSERT INTO shopping_lists (owner_ref, name) VALUES (:owner_ref, :name) "
            "RETURNING id"
        ),
        {"owner_ref": owner_ref, "name": name},
    ).mappings().first()
    conn.commit()
    return row["id"]


def list_lists(conn: Connection, owner_ref: str) -> list[dict]:
    rows = conn.execute(
        text(
            """
            SELECT
                sl.id, sl.name, sl.created_at, sl.updated_at,
                COUNT(sli.id) AS items_count
            FROM shopping_lists sl
            LEFT JOIN shopping_list_items sli ON sli.shopping_list_id = sl.id
            WHERE sl.owner_ref = :owner_ref
            GROUP BY sl.id
            ORDER BY sl.updated_at DESC
            """
        ),
        {"owner_ref": owner_ref},
    ).mappings().all()
    return [dict(row) for row in rows]


def get_list(conn: Connection, list_id: int, owner_ref: str) -> dict | None:
    row = conn.execute(
        text(
            "SELECT id, owner_ref, name, created_at, updated_at FROM shopping_lists "
            "WHERE id = :id AND owner_ref = :owner_ref"
        ),
        {"id": list_id, "owner_ref": owner_ref},
    ).mappings().first()
    return dict(row) if row else None


def rename_list(conn: Connection, list_id: int, owner_ref: str, name: str) -> bool:
    result = conn.execute(
        text(
            "UPDATE shopping_lists SET name = :name, updated_at = now() "
            "WHERE id = :id AND owner_ref = :owner_ref"
        ),
        {"id": list_id, "owner_ref": owner_ref, "name": name},
    )
    conn.commit()
    return result.rowcount > 0


def delete_list(conn: Connection, list_id: int, owner_ref: str) -> bool:
    result = conn.execute(
        text("DELETE FROM shopping_lists WHERE id = :id AND owner_ref = :owner_ref"),
        {"id": list_id, "owner_ref": owner_ref},
    )
    conn.commit()
    return result.rowcount > 0


def touch_list(conn: Connection, list_id: int) -> None:
    conn.execute(
        text("UPDATE shopping_lists SET updated_at = now() WHERE id = :id"),
        {"id": list_id},
    )
    conn.commit()


def add_item(
    conn: Connection,
    list_id: int,
    product_id: int | None,
    source_product_id: int | None,
    quantity: int,
) -> int:
    row = conn.execute(
        text(
            """
            INSERT INTO shopping_list_items
                (shopping_list_id, product_id, source_product_id, quantity)
            VALUES (:list_id, :product_id, :source_product_id, :quantity)
            RETURNING id
            """
        ),
        {
            "list_id": list_id,
            "product_id": product_id,
            "source_product_id": source_product_id,
            "quantity": quantity,
        },
    ).mappings().first()
    conn.commit()
    return row["id"]


def update_item_quantity(conn: Connection, item_id: int, list_id: int, quantity: int) -> bool:
    result = conn.execute(
        text(
            "UPDATE shopping_list_items SET quantity = :quantity "
            "WHERE id = :id AND shopping_list_id = :list_id"
        ),
        {"id": item_id, "list_id": list_id, "quantity": quantity},
    )
    conn.commit()
    return result.rowcount > 0


def delete_item(conn: Connection, item_id: int, list_id: int) -> bool:
    result = conn.execute(
        text(
            "DELETE FROM shopping_list_items WHERE id = :id AND shopping_list_id = :list_id"
        ),
        {"id": item_id, "list_id": list_id},
    )
    conn.commit()
    return result.rowcount > 0


def get_items(conn: Connection, list_id: int) -> list[dict]:
    rows = conn.execute(
        text(
            """
            SELECT
                sli.id, sli.quantity, sli.product_id, sli.source_product_id, sli.created_at,
                COALESCE(p.name, sp.name_raw) AS name,
                COALESCE(p.brand, sp.brand_raw) AS brand,
                sp.image_url
            FROM shopping_list_items sli
            LEFT JOIN products p ON p.id = sli.product_id
            LEFT JOIN source_products sp ON sp.id = sli.source_product_id
            WHERE sli.shopping_list_id = :list_id
            ORDER BY sli.created_at ASC
            """
        ),
        {"list_id": list_id},
    ).mappings().all()
    return [dict(row) for row in rows]


def get_cost_breakdown_rows(conn: Connection, list_id: int) -> list[dict]:
    """Una fila por (ítem, supermercado activo) con el precio disponible más
    reciente para ESE ítem en ESE supermercado, o NULL si no hay dato. La
    agregación por supermercado (suma, completitud) se hace en el servicio,
    no aquí, para mantener esta consulta reutilizable/legible."""
    rows = conn.execute(
        text(
            """
            SELECT
                sli.id AS item_id,
                sli.quantity,
                s.id AS supermarket_id,
                s.code AS supermarket_code,
                s.name AS supermarket_name,
                po.price
            FROM shopping_list_items sli
            CROSS JOIN supermarkets s
            LEFT JOIN LATERAL (
                SELECT sp.id
                FROM source_products sp
                WHERE sp.supermarket_id = s.id
                  AND (
                    (sli.source_product_id IS NOT NULL AND sp.id = sli.source_product_id)
                    OR (
                        sli.product_id IS NOT NULL
                        AND EXISTS (
                            SELECT 1 FROM product_matches pm
                            WHERE pm.source_product_id = sp.id
                              AND pm.product_id = sli.product_id
                              AND pm.status = 'CONFIRMED'
                        )
                    )
                  )
                LIMIT 1
            ) elegido ON TRUE
            LEFT JOIN LATERAL (
                SELECT price
                FROM price_observations
                WHERE source_product_id = elegido.id AND available = TRUE
                ORDER BY observed_at DESC
                LIMIT 1
            ) po ON elegido.id IS NOT NULL
            WHERE sli.shopping_list_id = :list_id AND s.is_active = TRUE
            """
        ),
        {"list_id": list_id},
    ).mappings().all()
    return [dict(row) for row in rows]
