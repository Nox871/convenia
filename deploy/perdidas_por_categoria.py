#!/usr/bin/env python3
"""Compara dos RAW de una tienda por categoría y muestra dónde se perdieron productos.

Uso (desde ~/convenia):
    scraper/.venv/bin/python deploy/perdidas_por_categoria.py jumbo 20261003 20261006
(las fechas son el prefijo del nombre del archivo: jumbo_raw_<fecha>T....json)
"""
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
tienda, antes, despues = sys.argv[1:4]


def cargar(prefijo):
    f = sorted((ROOT / "data" / "raw" / tienda / "productos").glob(f"{tienda}_raw_{prefijo}*.json"))[-1]
    d = json.load(open(f, encoding="utf8"))
    return d["products"] if isinstance(d, dict) else d


A, B = cargar(antes), cargar(despues)
ids_b = {p["product_id"] for p in B}
por_cat_a = Counter(p.get("category") for p in A)
por_cat_b = Counter(p.get("category") for p in B)
perdidos = [p for p in A if p["product_id"] not in ids_b]
sin_stock = sum(1 for p in perdidos if (p.get("seller_available_quantity") or 0) <= 0 and p.get("seller_available_quantity") is not None)
print(f"{tienda}: {len(A)} -> {len(B)}; se perdieron {len(perdidos)} productos ({sin_stock} de ellos ya tenían stock 0 en {antes}).")
print("\nCategorías que más perdieron (antes -> después):")
perdida = Counter()
for p in perdidos:
    perdida[p.get("category")] += 1
for cat, n in perdida.most_common(15):
    print(f"  -{n:4d}  {por_cat_a[cat]:5d} -> {por_cat_b[cat]:5d}  {str(cat)[:60]}")
print("\nCategorías que ya no aparecen:", sum(1 for c in por_cat_a if c not in por_cat_b), "de", len(por_cat_a))
