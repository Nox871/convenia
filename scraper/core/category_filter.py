"""Clasificador de categorías: decide si una categoría (por su nombre o
slug de URL) pertenece al alcance de "canasta familiar" de Convenia
(alimentación + aseo/hogar de consumo frecuente).

DISEÑO: palabras clave (no una lista rígida de categorías exactas), para
que sobreviva cambios de nomenclatura entre supermercados y no dependa de
enumerar cada categoría posible. Se aplica sobre CUALQUIER texto legible
de categoría disponible: el slug de la URL (D1, Éxito) o el nombre real
devuelto por el catálogo del supermercado (`categories`/`categoryId` de
VTEX en Éxito).

Regla de decisión (en este orden):
    1. Si el texto normalizado contiene alguna palabra de EXCLUSION -> False.
    2. Si contiene alguna palabra de INCLUSION -> True.
    3. Si no coincide con nada -> False (rechazo por defecto).

El rechazo por defecto es intencional: es preferible dejar fuera una
categoría desconocida que colar accidentalmente tecnología, moda, etc.
Ajustar el alcance más adelante es tan simple como añadir palabras a
`PALABRAS_INCLUSION` / `PALABRAS_EXCLUSION` — no requiere tocar el
scraper.
"""
from __future__ import annotations

import re
import unicodedata

# ============================================================
# NORMALIZACIÓN
# ============================================================


def normalizar_texto(texto: str | None) -> str:
    """minúsculas, sin acentos, sin separadores (-, _, /) -> espacios."""
    if not texto:
        return ""

    texto = unicodedata.normalize("NFKD", str(texto))
    texto = texto.encode("ascii", "ignore").decode("ascii")
    texto = texto.lower()
    texto = re.sub(r"[^a-z0-9]+", " ", texto)
    return re.sub(r"\s+", " ", texto).strip()


# ============================================================
# PALABRAS CLAVE
# ============================================================
#
# Cada entrada es un "stem": una palabra completa (para términos cortos o
# ambiguos, donde solo se acepta coincidencia EXACTA de palabra) o un
# prefijo de 4+ caracteres (para admitir género/plural: "verdur" agrupa
# verdura/verduras). Las frases con espacio se buscan como substring.

PALABRAS_INCLUSION = {
    # --- alimentación: básicos / despensa ---
    "arroz", "grano", "lenteja", "frijol", "garbanzo", "pasta", "fideo",
    "harina", "cereal", "avena", "azucar", "panela", "sal", "aceite",
    "vinagre", "salsa", "aderezo", "condiment", "enlatad", "conserv",
    "abarrote", "despensa", "mercados basicos",
    # nota: "hogar" a secas SÍ se incluye porque, verificado contra datos
    # reales de D1, su categoría "Hogar" es 100% aseo/limpieza (detergente,
    # servilletas, esponjas, bolsas) — no muebles/decoración. Esos casos se
    # excluyen explícitamente por frase ("hogar y decoracion") antes de
    # llegar a esta regla, porque la exclusión se evalúa primero.
    "hogar",
    # --- panadería / desayuno ---
    "panader", "pan", "galleta", "desayun", "cafe", "chocolate", "cacao",
    "cremas no lacteas",
    # --- bebidas no alcohólicas ---
    "bebida", "jugo", "gaseos", "refresco", "agua", "hidratante",
    # --- lácteos y huevos ---
    "lacte", "yogur", "kumis", "queso", "huevo",
    # --- carnes / proteína ---
    "carne", "res", "cerdo", "pollo", "pescad", "atun", "sardina",
    "embutid", "salchicha", "jamon", "mortadela", "delikatessen",
    # --- congelados ---
    "congelad",
    # --- frutas y verduras (frescos) ---
    "fruta", "verdur", "hortaliz", "tuberculo", "papa", "yuca", "platano",
    "legumbr", "frutas y verduras",
    # --- snacks ---
    "snack", "pasaboca", "mecato", "papas fritas",
    # --- aseo del hogar / consumo básico del hogar ---
    "aseo", "papel higienico", "papel de cocina", "servilleta",
    "detergente", "suavizante", "jabon", "lavaloza", "limpi", "desinfect",
    "bolsas de basura", "bolsa basura", "esponja", "escoba", "trapero",
    "ambientador", "blanqueador",
    # --- cuidado/aseo personal básico ---
    "cuidado personal", "higiene personal", "shampoo", "champu",
    "crema dental", "cepillo dental", "desodorante",
}

PALABRAS_EXCLUSION = {
    # tecnología / electrónica
    "tecnologia", "computador", "portatil", "celular", "smartphone",
    "television", "televisor", "videojuego", "consola", "electronic",
    "movilidad electrica", "electrodomestico",
    # hogar no consumible / decoración / muebles
    "decoracion", "mueble", "hogar y decoracion",
    # moda / calzado
    "moda", "ropa", "calzado", "zapato", "accesorios de moda",
    # entretenimiento / niños
    "juguete", "juego de mesa", "papeleria", "libro", "utiles escolares",
    # deportes / ferretería / vehículos
    "deporte", "fitness", "ferreteria", "herramienta", "vehiculo", "moto",
    # alcohol / tabaco
    "vino", "licor", "cerveza", "cigarrillo", "tabaco",
    # belleza / cosmética (distinto de aseo personal básico)
    "maquillaje", "perfum", "joyeria", "bisuteria",
    # otros verticales fuera de alcance
    "mascota", "bebe", "panal", "bazar", "servicios financieros",
    "tarjeta de credito", "seguro",
}


def _coincide(texto_normalizado: str, stem: str) -> bool:
    if " " in stem:
        return stem in texto_normalizado
    if len(stem) <= 3:
        return re.search(rf"\b{re.escape(stem)}\b", texto_normalizado) is not None
    return re.search(rf"\b{re.escape(stem)}", texto_normalizado) is not None


def es_categoria_relevante(texto: str | None) -> bool:
    """True si el texto de categoría pertenece al alcance de canasta familiar."""
    normalizado = normalizar_texto(texto)
    if not normalizado:
        return False

    if any(_coincide(normalizado, palabra) for palabra in PALABRAS_EXCLUSION):
        return False

    return any(_coincide(normalizado, palabra) for palabra in PALABRAS_INCLUSION)


def obtener_bucket(texto: str | None) -> str | None:
    """Devuelve la palabra clave de INCLUSIÓN que hizo relevante esta
    categoría (ej. "verdur", "lacte", "carne"), o None si no aplica.

    Sirve como agrupador grueso para homologación: solo tiene sentido
    comparar candidatos a "mismo producto" dentro del mismo bucket (no
    comparar un lácteo contra una verdura).
    """
    normalizado = normalizar_texto(texto)
    if not normalizado:
        return None

    if any(_coincide(normalizado, palabra) for palabra in PALABRAS_EXCLUSION):
        return None

    for palabra in PALABRAS_INCLUSION:
        if _coincide(normalizado, palabra):
            return palabra

    return None


def clasificar_categoria(texto: str | None) -> tuple[bool, str]:
    """Como `es_categoria_relevante`, pero devuelve también el motivo (para reportes/logs)."""
    normalizado = normalizar_texto(texto)
    if not normalizado:
        return False, "texto vacío"

    for palabra in PALABRAS_EXCLUSION:
        if _coincide(normalizado, palabra):
            return False, f"excluida por palabra clave '{palabra}'"

    for palabra in PALABRAS_INCLUSION:
        if _coincide(normalizado, palabra):
            return True, f"incluida por palabra clave '{palabra}'"

    return False, "no coincide con ninguna palabra clave (rechazo por defecto)"
