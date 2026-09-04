"""Motor de homologación: decide si dos `source_products` (de distinto
supermercado) representan el mismo producto canónico.

Señales usadas (ver `normalize.py`):
    - marca normalizada (si ambas existen)
    - similitud de texto del nombre base (sin marca ni cantidad)
    - cantidad/unidad normalizada (peso, volumen o conteo)

No se usa código de barras porque ninguno de los dos scrapers lo captura
hoy (ni `source_products` tiene esa columna) — no se inventa.

Diseño conservador: el umbral de CONFIRMED es alto a propósito. Es
preferible dejar un candidato en REVIEW que fusionar dos productos
distintos. Frutas/verduras y productos sin marca se evalúan igual, solo que
la marca simplemente no aporta puntaje (ni penaliza) cuando falta.
"""
from __future__ import annotations

import difflib
from dataclasses import dataclass

from .normalize import Cantidad, nombre_base, normalizar_marca, extraer_cantidad

CONFIRM_THRESHOLD = 0.80
REVIEW_THRESHOLD = 0.55


@dataclass(frozen=True)
class ProductoNormalizado:
    source_product_id: int
    supermarket_code: str
    name_raw: str
    marca: str | None
    cantidad: Cantidad | None
    nombre_base: str
    bucket_categoria: str | None


def construir_normalizado(
    source_product_id: int,
    supermarket_code: str,
    name_raw: str,
    brand_raw: str | None,
    bucket_categoria: str | None,
) -> ProductoNormalizado:
    marca = normalizar_marca(brand_raw)
    cantidad = extraer_cantidad(name_raw)
    base = nombre_base(name_raw, marca)
    return ProductoNormalizado(
        source_product_id=source_product_id,
        supermarket_code=supermarket_code,
        name_raw=name_raw,
        marca=marca,
        cantidad=cantidad,
        nombre_base=base,
        bucket_categoria=bucket_categoria,
    )


def _similitud_texto(a: str, b: str) -> float:
    if not a or not b:
        return 0.0

    secuencia = difflib.SequenceMatcher(None, a, b).ratio()

    tokens_a, tokens_b = set(a.split()), set(b.split())
    if tokens_a and tokens_b:
        jaccard = len(tokens_a & tokens_b) / len(tokens_a | tokens_b)
    else:
        jaccard = 0.0

    return 0.5 * secuencia + 0.5 * jaccard


@dataclass(frozen=True)
class ResultadoComparacion:
    score: float
    name_similarity: float
    marca_coincide: bool | None  # None = no evaluable (falta marca en algún lado)
    cantidad_coincide: bool | None
    status: str  # "CONFIRMED" | "REVIEW" | None (None = descartar, no persistir)
    motivo: str


def comparar(a: ProductoNormalizado, b: ProductoNormalizado) -> ResultadoComparacion:
    name_similarity = _similitud_texto(a.nombre_base, b.nombre_base)
    score = name_similarity * 0.55

    marca_coincide = None
    if a.marca and b.marca:
        marca_coincide = a.marca == b.marca
        if marca_coincide:
            score += 0.30
        else:
            # Marca real y distinta en ambos lados: señal fuerte de que NO
            # es el mismo producto, incluso si el nombre se parece mucho
            # (ej. "Arroz Diana" vs "Arroz Roa").
            score -= 0.35

    cantidad_coincide = None
    if a.cantidad and b.cantidad:
        if a.cantidad.compatible_con(b.cantidad):
            cantidad_coincide = a.cantidad.es_igual_a(b.cantidad)
            score += 0.15 if cantidad_coincide else -0.20
        else:
            # Dimensiones distintas (ej. peso vs conteo): no comparable,
            # pequeña penalización por incertidumbre.
            score -= 0.05

    score = max(0.0, min(1.0, score))

    if score >= CONFIRM_THRESHOLD and name_similarity >= 0.55:
        status = "CONFIRMED"
        motivo = f"nombre={name_similarity:.2f} marca={marca_coincide} cantidad={cantidad_coincide}"
    elif score >= REVIEW_THRESHOLD:
        status = "REVIEW"
        motivo = f"nombre={name_similarity:.2f} marca={marca_coincide} cantidad={cantidad_coincide}"
    else:
        status = None
        motivo = "score insuficiente"

    return ResultadoComparacion(
        score=score,
        name_similarity=name_similarity,
        marca_coincide=marca_coincide,
        cantidad_coincide=cantidad_coincide,
        status=status,
        motivo=motivo,
    )


def mejor_candidato(
    producto: ProductoNormalizado, candidatos: list[ProductoNormalizado]
) -> tuple[ProductoNormalizado, ResultadoComparacion] | None:
    """Compara `producto` contra cada candidato de la OTRA vitrina y
    devuelve el de mejor score, si supera REVIEW_THRESHOLD."""
    mejor = None
    mejor_resultado = None

    for candidato in candidatos:
        resultado = comparar(producto, candidato)
        if resultado.status is None:
            continue
        if mejor_resultado is None or resultado.score > mejor_resultado.score:
            mejor, mejor_resultado = candidato, resultado

    if mejor is None:
        return None
    return mejor, mejor_resultado
