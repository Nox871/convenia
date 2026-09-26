"""¿Puede un producto sustituir a otro en una lista de compras?

Una sugerencia de "cambia X por Y para ahorrar" sólo es honesta si Y es del
mismo TIPO de producto (misma base de nombre, sin marca ni cantidad) y de
tamaño parecido; si no, se estaría comparando peras con manzanas ("cambia la
leche de 900 ml por una de 250 ml porque es más barata"). Estas funciones son
puras (sin base de datos) para poder probarlas una a una.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from functools import cached_property

from app.core.category_bucket import normalizar_texto

# Mismas unidades que la homologación del ETL (etl/homologacion/normalize.py),
# copiadas aquí porque el backend no importa del ETL.
_PESO = {"g": 1, "gr": 1, "gramo": 1, "gramos": 1, "kg": 1000, "kilo": 1000, "kilos": 1000}
_VOLUMEN = {"ml": 1, "cc": 1, "l": 1000, "lt": 1000, "litro": 1000, "litros": 1000}
_CONTEO = {"un": 1, "und": 1, "unds": 1, "uds": 1, "unidad": 1, "unidades": 1, "u": 1}

_PATRON_CANTIDAD = re.compile(
    r"""
    (?:x\s*)?
    (\d+(?:[.,]\d+)?)
    \s*
    (gramos|gramo|kilos|kilo|kg|gr|g|
     litros|litro|lt|ml|cc|l|
     unidades|unidad|unds|uds|und|un|u)\b
    """,
    re.IGNORECASE | re.VERBOSE,
)

# Diferencia máxima de tamaño para considerar dos productos "del mismo tamaño".
TOLERANCIA_TAMANO = 0.10
# Cuánto más barato debe ser el sustituto para valer la sugerencia.
AHORRO_MINIMO = 0.05
# Parecido mínimo entre los nombres base (0-1).
PARECIDO_MINIMO = 0.6


@dataclass(frozen=True)
class Cantidad:
    dimension: str  # "peso" (g), "volumen" (ml) o "conteo" (unidades)
    valor: float


def extraer_cantidad(texto: str | None) -> Cantidad | None:
    """Primer "número + unidad" del texto, llevado a gramos, mililitros o unidades."""
    if not texto:
        return None
    match = _PATRON_CANTIDAD.search(texto)
    if not match:
        return None
    try:
        valor = float(match.group(1).replace(",", "."))
    except ValueError:
        return None
    unidad = match.group(2).lower()
    for tabla, dimension in ((_PESO, "peso"), (_VOLUMEN, "volumen"), (_CONTEO, "conteo")):
        if unidad in tabla:
            return Cantidad(dimension, valor * tabla[unidad])
    return None


def palabras_base(nombre: str, marca: str | None) -> list[str]:
    """Palabras que dicen QUÉ es el producto, en orden: el nombre sin la
    cantidad ni la marca ("Leche FRESCAMPO entera UHT (900 ml)" -> leche entera uht)."""
    texto = normalizar_texto(nombre)
    texto = _PATRON_CANTIDAD.sub(" ", texto)
    palabras = texto.split()
    marca_norm = set(normalizar_texto(marca).split()) if marca else set()
    return [p for p in palabras if p not in marca_norm and len(p) > 1 and not p.isdigit()]


def parecido(a: list[str], b: list[str]) -> float:
    """Índice de Jaccard entre las palabras base de dos productos."""
    sa, sb = set(a), set(b)
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)


def tamano_similar(a: Cantidad | None, b: Cantidad | None) -> bool:
    """Ambos sin cantidad se aceptan (frutas y verduras "por unidad"); si sólo
    uno la tiene, o son de distinta dimensión, no."""
    if a is None and b is None:
        return True
    if a is None or b is None or a.dimension != b.dimension:
        return False
    mayor = max(a.valor, b.valor)
    return mayor == 0 or abs(a.valor - b.valor) / mayor <= TOLERANCIA_TAMANO


@dataclass(frozen=True)
class Producto:
    """Lo mínimo de un producto para decidir si sustituye a otro."""

    nombre: str
    marca: str | None

    # Se calculan una sola vez por producto: al buscar sustitutos, cada candidato
    # se compara contra muchos ítems.
    @cached_property
    def base(self) -> list[str]:
        return palabras_base(self.nombre, self.marca)

    @cached_property
    def cantidad(self) -> Cantidad | None:
        return extraer_cantidad(self.nombre)

    @cached_property
    def marca_norm(self) -> str:
        return normalizar_texto(self.marca) if self.marca else ""


def es_mismo_producto(a: Producto, b: Producto) -> bool:
    """Misma marca, mismo nombre base y mismo tamaño: es el mismo producto (a lo
    sumo en otro supermercado), no un sustituto."""
    return (
        a.marca_norm == b.marca_norm
        and parecido(a.base, b.base) >= 0.999
        and tamano_similar(a.cantidad, b.cantidad)
    )


def puede_sustituir(original: Producto, candidato: Producto) -> bool:
    """Mismo tipo de producto y tamaño parecido, pero no el mismo producto."""
    if es_mismo_producto(original, candidato):
        return False
    return (
        parecido(original.base, candidato.base) >= PARECIDO_MINIMO
        and tamano_similar(original.cantidad, candidato.cantidad)
    )


def es_mas_barato(precio_actual: float, precio_candidato: float) -> bool:
    """Al menos `AHORRO_MINIMO` más barato: un ahorro de centavos no vale un cambio."""
    return precio_actual > 0 and precio_candidato <= precio_actual * (1 - AHORRO_MINIMO)
