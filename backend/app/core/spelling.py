"""Corrección de palabras mal escritas ("aroz", "arros" -> "arroz") contra el
vocabulario real de los nombres de producto.

Lógica pura (sin base de datos) para poder probarla: el vocabulario llega como
{palabra_sin_tildes: cuántos productos la usan}.
"""
from __future__ import annotations

import re
import unicodedata

# Una palabra que aparece en menos productos que esto no cuenta como "conocida":
# un error de tipeo en el catálogo no debe validar el error del usuario.
MIN_APARICIONES_CONOCIDA = 3
MIN_LARGO_PALABRA = 3


def sin_tildes(texto: str) -> str:
    nfd = unicodedata.normalize("NFD", texto.lower())
    return "".join(c for c in nfd if unicodedata.category(c) != "Mn")


def palabras(texto: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", sin_tildes(texto))


def distancia(a: str, b: str, maximo: int) -> int:
    """Distancia de edición con transposiciones (Damerau-Levenshtein "óptima"):
    cambiar dos letras contiguas de lugar ("caef" -> "cafe", "arorz" -> "arroz")
    cuenta como UN error, que es el que más se comete al escribir rápido.
    Devuelve maximo+1 si la distancia lo supera."""
    if abs(len(a) - len(b)) > maximo:
        return maximo + 1
    anterior2: list[int] | None = None
    anterior = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        actual = [i]
        for j, cb in enumerate(b, 1):
            costo = min(anterior[j] + 1, actual[j - 1] + 1, anterior[j - 1] + (ca != cb))
            if anterior2 is not None and i > 1 and j > 1 and ca == b[j - 2] and a[i - 2] == cb:
                costo = min(costo, anterior2[j - 2] + 1)
            actual.append(costo)
        if min(actual) > maximo:
            return maximo + 1
        anterior2, anterior = anterior, actual
    return anterior[-1]


def _maximo_errores(palabra: str) -> int:
    return 1 if len(palabra) <= 4 else 2


def corregir_palabra(palabra: str, vocabulario: dict[str, int]) -> str | None:
    """Palabra más parecida y más frecuente del vocabulario, o None si la
    palabra ya es conocida o no hay nada suficientemente cercano."""
    if len(palabra) < MIN_LARGO_PALABRA or palabra.isdigit():
        return None
    if vocabulario.get(palabra, 0) >= MIN_APARICIONES_CONOCIDA:
        return None

    maximo = _maximo_errores(palabra)
    mejor: tuple[int, int, str] | None = None  # (distancia, -apariciones, palabra)
    for candidata, veces in vocabulario.items():
        if veces < MIN_APARICIONES_CONOCIDA or len(candidata) < MIN_LARGO_PALABRA:
            continue
        d = distancia(palabra, candidata, maximo)
        if d > maximo:
            continue
        clave = (d, -veces, candidata)
        if mejor is None or clave < mejor:
            mejor = clave
    return mejor[2] if mejor else None


def sugerir_busqueda(texto: str, vocabulario: dict[str, int]) -> str | None:
    """Texto corregido palabra por palabra, o None si no hay nada que corregir."""
    originales = palabras(texto)
    if not originales:
        return None
    corregidas = []
    cambio = False
    for p in originales:
        c = corregir_palabra(p, vocabulario)
        if c is not None and c != p:
            cambio = True
            corregidas.append(c)
        else:
            corregidas.append(p)
    return " ".join(corregidas) if cambio else None
