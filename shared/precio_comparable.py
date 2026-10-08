"""Precios de cortes frescos que no se pueden comparar.

Algunos supermercados (Olímpica sobre todo) venden carne, pollo y pescado por
peso: el catálogo trae un precio "por unidad" que es un valor base (ej. $500 por
un lomo fino) o el de una pieza de peso desconocido (ej. un hueso a $2.500). Si
el nombre no declara cuánto pesa, ese número no dice cuánto cuesta lo que uno
se lleva y aparecía como "el más barato" de Carnes.
"""
from __future__ import annotations

import re

from .category_producto import CARNES, categoria_de_producto

# Debajo de esto, una carne/pollo/pescado sin peso declarado no es un precio real.
PISO_CARNE_SIN_PESO = 6000

_CANTIDAD = re.compile(
    r"\d+(?:[.,]\d+)?\s*(?:kg|kgs|kilos?|g|gr|grs|gramos?|lb|lbs|libras?|ml|l|lt|lts|litros?|un|und|unds|unidades)\b",
    re.IGNORECASE,
)


def tiene_cantidad_declarada(nombre: str | None) -> bool:
    return bool(nombre and _CANTIDAD.search(nombre))


def es_precio_no_comparable(nombre: str | None, ruta_categoria: str | None, precio) -> bool:
    """True si es carne/pollo/pescado sin peso en el nombre y con un precio
    por debajo de [PISO_CARNE_SIN_PESO]."""
    if precio is None or tiene_cantidad_declarada(nombre):
        return False
    if categoria_de_producto(nombre, ruta_categoria) != CARNES:
        return False
    return float(precio) < PISO_CARNE_SIN_PESO
