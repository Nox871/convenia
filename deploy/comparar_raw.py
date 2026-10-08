#!/usr/bin/env python3
"""Compara los archivos RAW de cada día: cuántos productos traen y cuántos de ellos
tienen precio mayor a 0. Sirve para saber si una caída de productos es real o sólo
el scraper dejando de traer productos agotados.

Uso (desde ~/convenia):  scraper/.venv/bin/python deploy/comparar_raw.py jumbo d1
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
for tienda in sys.argv[1:] or ["jumbo", "d1", "olimpica"]:
    print(f"\n== {tienda}")
    for f in sorted((ROOT / "data" / "raw" / tienda / "productos").glob(f"{tienda}_raw_*.json")):
        d = json.load(open(f, encoding="utf8"))
        ps = d["products"] if isinstance(d, dict) else d
        con_precio = sum(1 for p in ps if (p.get("price") or 0) > 0)
        con_stock = sum(
            1 for p in ps
            if (p.get("price") or 0) > 0 and (p.get("seller_available_quantity") is None or p["seller_available_quantity"] > 0)
        )
        print(f"  {f.stem[-17:]}  total={len(ps):6d}  con precio>0={con_precio:6d}  con precio y stock={con_stock:6d}")
