"""Verificación de integridad de los grupos de homologación.

Comprueba, sobre `products` + `product_matches` ya escritos en la base,
que ningún grupo canónico viola las reglas de homologación:

    1. No hay dos `source_products` del MISMO supermercado bajo un mismo
       `products.id` (la relación "~" no es transitiva: A~B y B~C no
       implica A~C -- ver etl/homologacion/run.py::_descomponer_en_subgrupos).
    2. Todos los miembros de un grupo tienen cantidad equivalente cuando
       ambos la tienen (misma dimensión y mismo valor dentro de tolerancia).

No hay framework de tests en el repo todavía; este script se ejecuta a
mano tras `python -m etl.homologacion.run`:

    python -m etl.homologacion.verificar_grupos

Sale con código 1 (y lista los grupos infractores) si encuentra alguna
violación; 0 si todo está limpio.
"""
from __future__ import annotations

import sys
from collections import defaultdict

from etl import db
from etl.homologacion.normalize import extraer_cantidad


def _cargar_grupos(conn) -> dict[int, list[tuple]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT pm.product_id, sp.id, s.code, sp.name_raw
            FROM product_matches pm
            JOIN source_products sp ON sp.id = pm.source_product_id
            JOIN supermarkets s ON s.id = sp.supermarket_id
            ORDER BY pm.product_id, s.code, sp.name_raw
            """
        )
        grupos: dict[int, list[tuple]] = defaultdict(list)
        for product_id, sp_id, code, name_raw in cur.fetchall():
            grupos[product_id].append((sp_id, code, name_raw))
        return grupos


def verificar() -> int:
    violaciones_super: list[tuple] = []
    violaciones_cantidad: list[tuple] = []

    with db.get_connection() as conn:
        grupos = _cargar_grupos(conn)

    for product_id, miembros in grupos.items():
        codes = [c for _, c, _ in miembros]
        duplicados = {c for c in codes if codes.count(c) > 1}
        if duplicados:
            violaciones_super.append((product_id, sorted(duplicados), miembros))

        cantidades = [
            (name, extraer_cantidad(name)) for _, _, name in miembros
        ]
        con_cantidad = [(n, q) for n, q in cantidades if q is not None]
        for i, (n_a, q_a) in enumerate(con_cantidad):
            for n_b, q_b in con_cantidad[i + 1:]:
                if not q_a.compatible_con(q_b) or not q_a.es_igual_a(q_b):
                    violaciones_cantidad.append((product_id, n_a, n_b))
                    break

    print(f"Grupos canónicos revisados: {len(grupos)}")
    print(f"Violaciones de supermercado duplicado: {len(violaciones_super)}")
    for product_id, dups, miembros in violaciones_super:
        print(f"  products.id={product_id} duplica {dups}")
        for m in miembros:
            print(f"      {m}")

    print(f"Violaciones de cantidad incompatible: {len(violaciones_cantidad)}")
    for product_id, n_a, n_b in violaciones_cantidad:
        print(f"  products.id={product_id}: '{n_a}' vs '{n_b}'")

    if violaciones_super or violaciones_cantidad:
        print("\nRESULTADO: FALLO -- hay grupos que violan las reglas de homologación")
        return 1

    print("\nRESULTADO: OK -- ningún grupo viola las reglas")
    return 0


if __name__ == "__main__":
    sys.exit(verificar())
