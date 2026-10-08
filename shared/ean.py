"""Código de barras (EAN/UPC/GTIN) de un producto: validación y clave común.

Los supermercados publican el EAN del fabricante en su catálogo VTEX. Dos
productos de tiendas distintas con el mismo EAN son el mismo artículo, sin
depender de cómo cada tienda escribe el nombre.

Sólo se aceptan códigos REALES de un fabricante: con dígito verificador
correcto y no de uso interno de la tienda (los de peso variable y los códigos
propios empiezan por 2 y no identifican un producto entre tiendas).
"""
from __future__ import annotations

import re

_LARGOS_VALIDOS = (8, 12, 13, 14)


def _digito_verificador_ok(gtin14: str) -> bool:
    cuerpo, verificador = gtin14[:-1], int(gtin14[-1])
    # GTIN: pesos 3,1,3,1,... empezando por la derecha del cuerpo
    suma = sum(int(d) * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(cuerpo)))
    return (10 - suma % 10) % 10 == verificador


def normalizar_ean(valor: object) -> str | None:
    """EAN como clave de 14 dígitos (EAN-8/UPC-12/EAN-13 se rellenan con ceros a
    la izquierda), o None si no es un código de fabricante utilizable."""
    if valor is None:
        return None
    digitos = re.sub(r"\D", "", str(valor))
    if len(digitos) not in _LARGOS_VALIDOS:
        return None
    if len(set(digitos)) == 1:  # 0000000000000, 1111111111111...
        return None
    clave = digitos.zfill(14)
    if not _digito_verificador_ok(clave):
        return None
    # Prefijo 2 (EAN-13): códigos de uso interno / peso variable de la tienda.
    if len(digitos) <= 13 and digitos.zfill(13)[0] == "2":
        return None
    return clave
