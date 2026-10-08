#!/usr/bin/env python3
"""Pasa los RAW históricos de una tienda por los filtros ACTUALES del ETL (sin tocar la
base de datos) y cuenta cuántos productos quedarían. Sirve para saber si una caída de
productos se debe a los filtros (intencional) o a que el scraper trajo menos.

Uso (desde ~/convenia):  scraper/.venv/bin/python deploy/simular_filtros.py jumbo
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from etl.core import SupermarketETL  # noqa: E402

for tienda in sys.argv[1:] or ["jumbo"]:
    print(f"\n== {tienda}: archivo -> RAW | tras los filtros de hoy | con precio>0 al final")
    etl = SupermarketETL.__new__(SupermarketETL)
    etl.code = tienda.upper()
    for f in sorted((ROOT / "data" / "raw" / tienda / "productos").glob(f"{tienda}_raw*.json")):
        d = json.load(open(f, encoding="utf8"))
        ps = d["products"] if isinstance(d, dict) else d
        filtrados = etl._filtrar_productos(list(ps))
        con_precio = sum(1 for p in filtrados if (p.get("price") or 0) > 0)
        print(f"  {f.stem[-17:]:17s}  RAW={len(ps):6d}  filtrados={len(filtrados):6d}  con precio={con_precio:6d}")
