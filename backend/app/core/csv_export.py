"""Formato del CSV de historial de precios.

Separador ";" y BOM UTF-8: es lo que Excel en español (configuración regional de
Colombia) abre correctamente con doble clic, con tildes bien y una columna por
campo. Para pandas: `pd.read_csv(archivo, sep=";", encoding="utf-8-sig")`.
"""
from __future__ import annotations

import csv
import io
from datetime import datetime
from decimal import Decimal
from typing import Iterable

BOM = "\ufeff"
DELIMITER = ";"

HEADERS = [
    "fecha_observacion",
    "supermercado_codigo",
    "supermercado",
    "producto",
    "marca",
    "categoria",
    "precio",
    "precio_lista",
    "moneda",
    "disponible",
    "id_producto_fuente",
    "url_producto",
]


def format_price(value: float | Decimal | int | None) -> str:
    """Precio sin ceros de más: 4120 en vez de 4120.0; con decimales solo si los
    tiene, siempre con punto (sin separador de miles)."""
    if value is None:
        return ""
    number = float(value)
    return str(int(number)) if number == int(number) else f"{number:.2f}"


def format_row(row: dict, category: str | None) -> list[str]:
    observed = row["observed_at"]
    return [
        observed.isoformat(timespec="seconds") if isinstance(observed, datetime) else str(observed),
        row["supermarket_code"],
        row["supermarket_name"],
        row["name"] or "",
        row["brand"] or "",
        category or "",
        format_price(row["price"]),
        format_price(row["list_price"]),
        row["currency"] or "",
        "si" if row["available"] else "no",
        str(row["source_product_id"]),
        row["product_url"] or "",
    ]


def encode_csv(rows: Iterable[list[str]]) -> str:
    """Convierte filas ya formateadas en texto CSV (sin BOM)."""
    buffer = io.StringIO()
    writer = csv.writer(buffer, delimiter=DELIMITER, lineterminator="\r\n")
    writer.writerows(rows)
    return buffer.getvalue()
