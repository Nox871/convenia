"""Normalización de nombre/marca/cantidad para homologación.

Reutiliza `normalizar_texto` del clasificador de categorías del scraper
(mismo criterio: minúsculas, sin acentos, sin separadores) para no duplicar
la definición de "normalizar texto" en dos lugares del proyecto.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal

from scraper.core.category_filter import normalizar_texto

# ============================================================
# MARCA
# ============================================================

# Señales de que `brand_raw` no es una marca real sino basura capturada por
# heurísticas del scraper (visto en datos reales de D1: la línea markdown de
# una imagen quedó como "marca" en algunos productos de Hogar/Cuidado
# personal). Se limpia aquí, en homologación, para no romper el ETL ni
# tocar el scraper por un problema que solo afecta al matching.
_MARCA_INVALIDA = re.compile(r"!\[|http[s]?://|\.png|\.jpg|\.jpeg", re.IGNORECASE)


def normalizar_marca(brand_raw: str | None) -> str | None:
    if not brand_raw:
        return None
    if _MARCA_INVALIDA.search(brand_raw):
        return None
    texto = normalizar_texto(brand_raw)
    return texto or None


# ============================================================
# CANTIDAD / UNIDAD
# ============================================================

_UNIDADES_PESO = {"g": 1, "gr": 1, "gramo": 1, "gramos": 1, "kg": 1000, "kilo": 1000, "kilos": 1000}
_UNIDADES_VOLUMEN = {"ml": 1, "cc": 1, "l": 1000, "lt": 1000, "litro": 1000, "litros": 1000}
_UNIDADES_CONTEO = {"un": 1, "und": 1, "unds": 1, "uds": 1, "unidad": 1, "unidades": 1, "u": 1, "x": 1}

_PATRON_CANTIDAD = re.compile(
    r"""
    (?:x\s*)?                      # "X6" (multiplicador sin unidad explícita)
    (\d+(?:[.,]\d+)?)              # número
    \s*
    (gramos|gramo|kilos|kilo|kg|gr|g|
     litros|litro|lt|ml|cc|l|
     unidades|unidad|unds|uds|und|un|u)\b
    """,
    re.IGNORECASE | re.VERBOSE,
)


@dataclass(frozen=True)
class Cantidad:
    valor: Decimal
    dimension: str  # "peso" (base: gramos), "volumen" (base: ml), "conteo" (base: unidades)

    def compatible_con(self, otra: "Cantidad") -> bool:
        return self.dimension == otra.dimension

    def es_igual_a(self, otra: "Cantidad", tolerancia: float = 0.05) -> bool:
        if not self.compatible_con(otra):
            return False
        mayor = max(self.valor, otra.valor)
        if mayor == 0:
            return self.valor == otra.valor
        return abs(self.valor - otra.valor) / mayor <= tolerancia


def extraer_cantidad(texto: str) -> Cantidad | None:
    """Busca un patrón numero+unidad en el texto y lo lleva a una unidad
    base por dimensión (gramos / mililitros / unidades), para poder
    comparar "1 Kg" con "1000 G", o "2500 Grs" con "2.5 Kg"."""
    if not texto:
        return None

    match = _PATRON_CANTIDAD.search(texto)
    if not match:
        return None

    valor_texto, unidad_texto = match.groups()
    try:
        valor = Decimal(valor_texto.replace(",", "."))
    except Exception:
        return None

    unidad = unidad_texto.lower()

    if unidad in _UNIDADES_PESO:
        return Cantidad(valor=valor * _UNIDADES_PESO[unidad], dimension="peso")
    if unidad in _UNIDADES_VOLUMEN:
        return Cantidad(valor=valor * _UNIDADES_VOLUMEN[unidad], dimension="volumen")
    if unidad in _UNIDADES_CONTEO:
        return Cantidad(valor=valor * _UNIDADES_CONTEO[unidad], dimension="conteo")

    return None


# ============================================================
# NOMBRE BASE (sin marca, sin cantidad) — para comparar por similitud
# ============================================================


def nombre_base(name_raw: str, marca: str | None) -> str:
    """Normaliza el nombre y le quita la marca y el patrón de cantidad, para
    quedarse con el "núcleo" del producto (ej. "arroz diana 500 g" ->
    "arroz"). No se usa para mostrar nada al usuario, solo para comparar."""
    texto = normalizar_texto(name_raw)

    texto_sin_cantidad = _PATRON_CANTIDAD.sub(" ", texto)

    if marca:
        # La marca puede aparecer como palabra suelta dentro del nombre.
        texto_sin_cantidad = re.sub(
            rf"\b{re.escape(marca)}\b", " ", texto_sin_cantidad
        )

    texto_final = re.sub(r"\s+", " ", texto_sin_cantidad).strip()
    return texto_final or texto
