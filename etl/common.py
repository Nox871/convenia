"""Utilidades compartidas por los ETL de D1 y Éxito."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal, InvalidOperation
import unicodedata


@dataclass
class ETLStats:
    raw_count: int = 0
    processed: int = 0
    products_inserted: int = 0
    products_updated: int = 0
    categories_new: int = 0
    categories_seen: int = 0
    prices_inserted: int = 0
    prices_duplicated: int = 0
    errors: int = 0
    error_details: list = field(default_factory=list)

    def print_report(self, supermarket_code: str) -> None:
        print(f"\nETL {supermarket_code}")
        print("-" * 30)
        print(f"RAW: {self.raw_count}")
        print(f"Procesados: {self.processed}")
        print(f"Insertados: {self.products_inserted}")
        print(f"Actualizados: {self.products_updated}")
        print(f"Categorías: {self.categories_seen} (nuevas: {self.categories_new})")
        print(f"Precios insertados: {self.prices_inserted}")
        print(f"Precios duplicados: {self.prices_duplicated}")
        print(f"Errores: {self.errors}")
        print("-" * 30)
        print("FINALIZADO")


def normalize_str(value) -> str | None:
    """Recorta espacios y convierte strings vacíos en None. No altera el contenido real."""
    if value is None:
        return None
    if not isinstance(value, str):
        value = str(value)
    value = value.strip()
    return value or None


def to_decimal(value) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise ValueError(f"Valor numérico inválido: {value!r}")


def parse_timestamp(value) -> datetime | None:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        raise ValueError(f"Timestamp inválido: {value!r}")


def normalize_payment_methods(value) -> list:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    raise ValueError(f"payment_methods debe ser una lista, se recibió: {type(value)!r}")


def slugify(text: str) -> str:
    """Genera una clave determinista y legible a partir de un texto (sin inventar IDs)."""
    normalized = unicodedata.normalize("NFKD", text)
    ascii_text = normalized.encode("ascii", "ignore").decode("ascii")
    ascii_text = ascii_text.strip().lower()
    slug_chars = []
    prev_dash = False
    for ch in ascii_text:
        if ch.isalnum():
            slug_chars.append(ch)
            prev_dash = False
        elif not prev_dash:
            slug_chars.append("-")
            prev_dash = True
    return "".join(slug_chars).strip("-") or "sin-categoria"
