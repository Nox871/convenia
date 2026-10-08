"""Limpieza de la marca que publica cada tienda.

Algunos catálogos traen en el campo "marca" basura: una imagen en markdown
("![](https://...)"), una URL o un nombre de archivo. Eso se mostraba tal cual
como marca del producto. Aquí se descarta: sin marca es mejor que una marca
falsa.
"""
from __future__ import annotations

import re

# Textos que ocupan el lugar de una marca pero no son una marca.
_SIN_MARCA = {"sin marca", "sinmarca", "generico", "genérico", "s/m", "n/a", "na", "ninguna", "ninguno", "null", "none", "-"}

_BASURA = re.compile(r"!\[|\]\(|https?:|www\.|\.(?:png|jpe?g|webp|gif|svg)\b", re.IGNORECASE)


def limpiar_marca(valor: object) -> str | None:
    """Marca limpia, o None si viene vacía o es basura (markdown, URL, archivo)."""
    if valor is None:
        return None
    texto = " ".join(str(valor).split())
    if not texto or _BASURA.search(texto) or len(texto) > 60 or texto.lower() in _SIN_MARCA:
        return None
    return texto
