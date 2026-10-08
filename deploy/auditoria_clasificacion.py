#!/usr/bin/env python3
"""Auditoría de categorías (SOLO LECTURA).

Muestra dónde la clasificación por nombre NO alcanza y se heredó el pasillo del
supermercado (la causa de casi todos los errores), y los productos cuyo nombre y
pasillo dicen categorías distintas.

Uso (desde ~/convenia):
    scraper/.venv/bin/python deploy/auditoria_clasificacion.py
"""
from __future__ import annotations

import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from etl.db import get_connection  # noqa: E402
from shared.category_producto import (  # noqa: E402
    _etiqueta_por_pasillo,
    _normalizar,
    categoria_de_producto,
    categoria_por_nombre,
)


def main() -> None:
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT sp.name_raw, sc.name_raw
            FROM source_products sp
            LEFT JOIN source_categories sc ON sc.id = sp.source_category_id
            WHERE sp.status = 'ACTIVE'
            """
        )
        filas = cur.fetchall()

    por_categoria: Counter = Counter()
    respaldo: dict[str, list] = defaultdict(lambda: [0, Counter(), ""])
    desacuerdos: dict[tuple, list[str]] = defaultdict(list)
    for nombre, ruta in filas:
        final = categoria_de_producto(nombre, ruta)
        por_categoria[final] += 1
        por_nombre = categoria_por_nombre(nombre)
        if por_nombre is None and final is not None:
            cabeza = (_normalizar(nombre or "").split(" ", 1) or [""])[0]
            e = respaldo[cabeza]
            e[0] += 1
            e[1][final] += 1
            e[2] = e[2] or (nombre or "")
        pasillo = _etiqueta_por_pasillo(ruta)
        if por_nombre and pasillo and por_nombre != pasillo:
            desacuerdos[(por_nombre, pasillo)].append(nombre or "")

    print(f"\nProductos activos: {len(filas)}")
    print("\n=== Por categoría ===")
    for cat, n in por_categoria.most_common():
        print(f"  {n:6d}  {cat}")

    total = sum(v[0] for v in respaldo.values())
    print(f"\n=== Productos clasificados SOLO por el pasillo ({total}): primera palabra que falta ===")
    for cabeza, (n, cats, ej) in sorted(respaldo.items(), key=lambda x: -x[1][0])[:60]:
        print(f"  {n:4d}  {cabeza:14s} -> {dict(cats.most_common(2))}   ej: {ej[:55]}")

    print("\n=== Nombre y pasillo no coinciden (ejemplos) ===")
    for clave, nombres in sorted(desacuerdos.items(), key=lambda x: -len(x[1]))[:10]:
        print(f"  nombre={clave[0]} | pasillo={clave[1]}  ({len(nombres)})")
        for n in nombres[:5]:
            print(f"        {n[:62]}")


if __name__ == "__main__":
    main()
