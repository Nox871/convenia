#!/usr/bin/env python3
"""Auditoría 2 (SOLO LECTURA): ¿entra a la base lo que no es canasta?, ¿hay
duplicados?, ¿la homologación se pierde matches evidentes?

Uso (desde ~/convenia):  scraper/.venv/bin/python deploy/auditoria_categorias.py
"""
from __future__ import annotations

import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from etl.db import get_connection  # noqa: E402
from shared.category_producto import categoria_de_producto  # noqa: E402


def titulo(t: str) -> None:
    print(f"\n=== {t} ===")


def main() -> None:
    with get_connection() as conn:
        cur = conn.cursor()

        titulo("A. Productos ACTIVE por tienda según la categoría amigable (None = fuera de canasta)")
        cur.execute(
            """
            SELECT s.code, sp.id, sp.name_raw, sc.name_raw
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            LEFT JOIN source_categories sc ON sc.id = sp.source_category_id
            WHERE sp.status = 'ACTIVE'
            """
        )
        por_tienda = defaultdict(Counter)
        fuera = defaultdict(list)
        for code, _id, nombre, ruta in cur.fetchall():
            etiqueta = categoria_de_producto(nombre, ruta)
            por_tienda[code][etiqueta or "(FUERA DE CANASTA)"] += 1
            if etiqueta is None:
                fuera[code].append((ruta or "(sin pasillo)", nombre))
        for code in sorted(por_tienda):
            total = sum(por_tienda[code].values())
            n_fuera = por_tienda[code]["(FUERA DE CANASTA)"]
            print(f"\n{code}: {total} activos, {n_fuera} fuera de canasta ({100*n_fuera/max(total,1):.0f} %)")
            for et, n in por_tienda[code].most_common(14):
                print(f"   {n:6d}  {et}")

        titulo("B. Pasillos 'fuera de canasta' más frecuentes por tienda (con 2 ejemplos)")
        for code in sorted(fuera):
            pasillos = Counter(r for r, _ in fuera[code])
            print(f"\n{code}:")
            for ruta, n in pasillos.most_common(10):
                ej = [nm for r, nm in fuera[code] if r == ruta][:2]
                print(f"   {n:5d}  {ruta[:60]}  | ej: {' / '.join(e[:38] for e in ej)}")

        titulo("C. Duplicados: mismo supermercado y mismo nombre, distinto id (10 ejemplos)")
        cur.execute(
            """
            SELECT s.code, d.n, d.cnt, d.ids, d.precios
            FROM (
              SELECT supermarket_id, lower(name_raw) AS n, count(*) AS cnt,
                     string_agg(sp.external_id, ', ') AS ids,
                     string_agg(coalesce((SELECT price::text FROM price_observations po
                         WHERE po.source_product_id = sp.id ORDER BY observed_at DESC LIMIT 1), '-'), ', ') AS precios
              FROM source_products sp WHERE status = 'ACTIVE'
              GROUP BY supermarket_id, lower(name_raw) HAVING count(*) > 1
            ) d JOIN supermarkets s ON s.id = d.supermarket_id
            ORDER BY d.cnt DESC LIMIT 10
            """
        )
        for code, n, cnt, ids, precios in cur.fetchall():
            print(f"   {code:9s} x{cnt}  ids=[{ids[:40]}] precios=[{precios[:40]}]  {n[:60]}")

        titulo("D. Homologación: estados de los matches")
        cur.execute("SELECT status, match_method, count(*) FROM product_matches GROUP BY 1, 2 ORDER BY 3 DESC")
        for r in cur.fetchall():
            print("  ", r)

        titulo("E. Productos activos SIN match que tienen en OTRA tienda un activo con NOMBRE IDÉNTICO")
        cur.execute(
            """
            SELECT s.code, count(*) FROM source_products a
            JOIN supermarkets s ON s.id = a.supermarket_id
            WHERE a.status = 'ACTIVE'
              AND NOT EXISTS (SELECT 1 FROM product_matches m WHERE m.source_product_id = a.id AND m.status = 'CONFIRMED')
              AND EXISTS (SELECT 1 FROM source_products b
                          WHERE b.status = 'ACTIVE' AND b.supermarket_id <> a.supermarket_id
                            AND lower(b.name_raw) = lower(a.name_raw))
            GROUP BY 1 ORDER BY 1
            """
        )
        for r in cur.fetchall():
            print("  ", r)

        titulo("F. Matches CONFIRMED que apuntan a productos que ya no están activos")
        cur.execute(
            """
            SELECT s.code, sp.status, count(*) FROM product_matches pm
            JOIN source_products sp ON sp.id = pm.source_product_id
            JOIN supermarkets s ON s.id = sp.supermarket_id
            WHERE pm.status = 'CONFIRMED' AND sp.status <> 'ACTIVE'
            GROUP BY 1, 2 ORDER BY 1, 2
            """
        )
        for r in cur.fetchall():
            print("  ", r)


if __name__ == "__main__":
    main()
