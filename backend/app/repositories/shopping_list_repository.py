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

from app.core.ownership import account_owner_ref, user_id_from_owner_ref


def create_list(conn: Connection, owner_ref: str, name: str) -> int:
    row = conn.execute(
        text(
            "INSERT INTO shopping_lists (owner_ref, user_id, name) VALUES (:owner_ref, :user_id, :name) "
            "RETURNING id"
        ),
        {"owner_ref": owner_ref, "user_id": user_id_from_owner_ref(owner_ref), "name": name},
    ).mappings().first()
    conn.commit()
    return row["id"]


def list_lists(conn: Connection, owner_ref: str) -> list[dict]:
    rows = conn.execute(
        text(
            """
            SELECT
                sl.id, sl.name, sl.created_at, sl.updated_at, sl.budget,
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
            "SELECT id, owner_ref, name, created_at, updated_at, budget FROM shopping_lists "
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


def set_budget(conn: Connection, list_id: int, owner_ref: str, budget: int | None) -> bool:
    result = conn.execute(
        text(
            "UPDATE shopping_lists SET budget = :budget, updated_at = now() "
            "WHERE id = :id AND owner_ref = :owner_ref"
        ),
        {"id": list_id, "owner_ref": owner_ref, "budget": budget},
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
    # Si el producto ya está en la lista, se suma la cantidad en vez de
    # crear un renglón repetido ("arroz" dos veces).
    existing = conn.execute(
        text(
            """
            UPDATE shopping_list_items
            SET quantity = quantity + :quantity
            WHERE shopping_list_id = :list_id
              AND product_id IS NOT DISTINCT FROM :product_id
              AND source_product_id IS NOT DISTINCT FROM :source_product_id
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
    if existing is not None:
        conn.commit()
        return existing["id"]

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
                -- Un ítem canónico (product_id) no tiene imagen propia: se toma
                -- la de alguno de los productos de supermercado ya homologados
                -- a él. Sin esto, todo lo que se agrega desde las sugerencias
                -- (canónicos) aparecía sin foto.
                COALESCE(sp.image_url, img.image_url) AS image_url
            FROM shopping_list_items sli
            LEFT JOIN products p ON p.id = sli.product_id
            LEFT JOIN source_products sp ON sp.id = sli.source_product_id
            LEFT JOIN LATERAL (
                SELECT sp2.image_url
                FROM product_matches pm
                JOIN source_products sp2 ON sp2.id = pm.source_product_id
                WHERE pm.product_id = sli.product_id
                  AND pm.status = 'CONFIRMED'
                  AND sp2.image_url IS NOT NULL
                ORDER BY sp2.id
                LIMIT 1
            ) img ON sli.product_id IS NOT NULL
            WHERE sli.shopping_list_id = :list_id
            ORDER BY sli.created_at ASC
            """
        ),
        {"list_id": list_id},
    ).mappings().all()
    return [dict(row) for row in rows]


def get_cost_breakdown_rows(
    conn: Connection, list_id: int, supermarket_codes: list[str] | None = None
) -> list[dict]:
    """Una fila por (ítem, supermercado activo) con el precio disponible más
    reciente para ESE ítem en ESE supermercado, o NULL si no hay dato. La
    agregación por supermercado (suma, completitud) se hace en el servicio,
    no aquí, para mantener esta consulta reutilizable/legible."""
    scope = "" if supermarket_codes is None else "AND s.code = ANY(:sm_codes)"
    rows = conn.execute(
        text(
            f"""
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
                WHERE sp.supermarket_id = s.id AND sp.status = 'ACTIVE'
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
                WHERE source_product_id = elegido.id AND available = TRUE AND price > 0
                ORDER BY observed_at DESC
                LIMIT 1
            ) po ON elegido.id IS NOT NULL
            WHERE sli.shopping_list_id = :list_id AND s.is_active = TRUE {scope}
            """
        ),
        {"list_id": list_id, "sm_codes": supermarket_codes},
    ).mappings().all()
    return [dict(row) for row in rows]


def claim_device_lists(conn: Connection, device_ref: str, user_id: int) -> int:
    """Pasa a `user_id` las listas del dispositivo que aún no tienen cuenta."""
    result = conn.execute(
        text(
            "UPDATE shopping_lists SET owner_ref = :account_ref, user_id = :user_id "
            "WHERE owner_ref = :device_ref AND user_id IS NULL"
        ),
        {"account_ref": account_owner_ref(user_id), "user_id": user_id, "device_ref": device_ref},
    )
    conn.commit()
    return result.rowcount
