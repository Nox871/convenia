"""Clasificador de categorías: decide si una categoría (por su nombre o
slug de URL) pertenece al alcance de "canasta familiar" de Convenia
(alimentación + aseo/hogar de consumo frecuente).

Vive en `shared/` (sin ninguna dependencia externa, sólo stdlib) para poder
importarse tanto desde `scraper/` y `etl/` (que sí instalan crawl4ai,
psycopg2, etc. en su propio venv) como desde `backend/` (que tiene su propio
venv separado y no depende del scraper). `scraper/core/category_filter.py`
re-exporta este módulo para no romper los imports existentes de los 5
conectores y de `etl/homologacion/run.py`.

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
from urllib.parse import unquote

# ============================================================
# NORMALIZACIÓN
# ============================================================


def normalizar_texto(texto: str | None) -> str:
    """minúsculas, sin acentos, sin separadores (-, _, /) -> espacios.

    Decodifica primero secuencias porcentuales de URL (ej. "decoraci%C3%B3n"
    -> "decoración"), porque algunos supermercados devuelven segmentos de
    ruta sin decodificar y, sin este paso, una categoría acentuada como
    "Hogar y decoración" nunca coincidiría con la frase de exclusión
    "hogar y decoracion" (quedaría como "decoraci c3 b3n").
    """
    if not texto:
        return ""

    try:
        texto = unquote(str(texto))
    except Exception:
        texto = str(texto)

    texto = unicodedata.normalize("NFKD", texto)
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

# Tupla (no set) A PROPÓSITO: `obtener_bucket` devuelve la PRIMERA palabra que
# coincide, así que el orden importa y debe ser estable entre procesos. Con un
# set, el orden de iteración depende de PYTHONHASHSEED y una misma categoría
# (ej. ".../Gaseosas y bebidas/Té Líquido/", que contiene "bebida", "gaseos" y
# "snack") caía en un bucket distinto en cada corrida -> la homologación no
# convergía. El orden de abajo ES la prioridad: lo más genérico/seguro primero.
PALABRAS_INCLUSION = (
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
    "lacte", "yogur", "kumis", "queso", "huevo", "refrigerado",
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
)

# Set: aquí sólo se hacen pruebas de pertenencia con `any(...)`, el orden no
# influye en el resultado.
PALABRAS_EXCLUSION = {
    # tecnología / electrónica
    "tecnologia", "computador", "portatil", "celular", "smartphone",
    "television", "televisor", "videojuego", "consola", "electronic",
    "movilidad electrica", "electrodomestico", "electro hogar", "electrohogar",
    # hogar no consumible / decoración / muebles / menaje-cocina no consumible
    "decoracion", "mueble", "hogar y decoracion", "hogar cocina",
    "equipos hogar", "pintura",
    # moda / calzado / vestuario
    "moda", "ropa", "calzado", "zapato", "accesorios de moda", "vestuario",
    # entretenimiento / niños
    "juguete", "juego de mesa", "papeleria", "libro", "utiles escolares",
    # deportes / ferretería / vehículos
    "deporte", "fitness", "ferreteria", "herramienta", "vehiculo", "moto",
    "automovil", "automotriz",
    # alcohol / tabaco
    "vino", "licor", "cerveza", "cigarrillo", "tabaco",
    # belleza / cosmética (distinto de aseo personal básico)
    "maquillaje", "perfum", "joyeria", "bisuteria",
    # salud / cuidado médico (distinto de aseo personal básico)
    "cuidado en casa", "paciente", "equipos medicos", "farmacia", "medicamento",
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


# ============================================================
# DENSIDAD DE CATEGORÍA (paginación dinámica)
# ============================================================
#
# "Despensa"/"abarrotes" concentra muchísimas más referencias que, por
# ejemplo, pescados frescos o frutas y verduras. Un límite de páginas fijo
# e igual para todas las categorías captura el catálogo completo de las
# categorías pequeñas pero trunca las grandes a solo sus primeros
# productos (los más vendidos/patrocinados). Este factor se multiplica por
# `MAX_PAGINAS_POR_CATEGORIA` de cada scraper para compensarlo, sin tocar
# el límite de las categorías de bajo volumen.

PALABRAS_ALTA_DENSIDAD = {"despensa", "abarrote", "mercados basicos"}

FACTOR_PAGINAS_ALTA_DENSIDAD = 5


def factor_paginas(texto: str | None) -> int:
    """Multiplicador de páginas para `texto` (nombre/slug de categoría).
    Devuelve `FACTOR_PAGINAS_ALTA_DENSIDAD` para despensa/abarrotes, 1 para
    el resto."""
    normalizado = normalizar_texto(texto)
    if not normalizado:
        return 1
    if any(_coincide(normalizado, palabra) for palabra in PALABRAS_ALTA_DENSIDAD):
        return FACTOR_PAGINAS_ALTA_DENSIDAD
    return 1


# ============================================================
# ETIQUETA AMIGABLE (para el consumidor, nunca la ruta técnica cruda)
# ============================================================
#
# `obtener_bucket()` devuelve el STEM de coincidencia (ej. "verdur", "lacte"),
# útil como clave de agrupación interna pero no presentable. Este mapeo
# traduce cada stem de `PALABRAS_INCLUSION` a una etiqueta en español que sí
# puede mostrarse en la app -- nunca se expone `source_categories.name_raw`
# (ej. "/Despensa/Granos/Arroz/") directamente al usuario.

ETIQUETAS_AMIGABLES = {
    # despensa / básicos
    "arroz": "Despensa", "grano": "Despensa", "lenteja": "Despensa",
    "frijol": "Despensa", "garbanzo": "Despensa", "pasta": "Despensa",
    "fideo": "Despensa", "harina": "Despensa", "cereal": "Despensa",
    "avena": "Despensa", "azucar": "Despensa", "panela": "Despensa",
    "sal": "Despensa", "aceite": "Despensa", "vinagre": "Despensa",
    "salsa": "Despensa", "aderezo": "Despensa", "condiment": "Despensa",
    "enlatad": "Despensa", "conserv": "Despensa", "abarrote": "Despensa",
    "despensa": "Despensa", "mercados basicos": "Despensa",
    # panadería / desayuno
    "panader": "Panadería y desayuno", "pan": "Panadería y desayuno",
    "galleta": "Panadería y desayuno", "desayun": "Panadería y desayuno",
    "cafe": "Panadería y desayuno", "chocolate": "Panadería y desayuno",
    "cacao": "Panadería y desayuno", "cremas no lacteas": "Panadería y desayuno",
    # bebidas no alcohólicas
    "bebida": "Bebidas", "jugo": "Bebidas", "gaseos": "Bebidas",
    "refresco": "Bebidas", "agua": "Bebidas", "hidratante": "Bebidas",
    # lácteos y huevos
    "lacte": "Lácteos y huevos", "yogur": "Lácteos y huevos",
    "kumis": "Lácteos y huevos", "queso": "Lácteos y huevos",
    "huevo": "Lácteos y huevos", "refrigerado": "Lácteos y huevos",
    # carnes / proteína
    "carne": "Carnes y embutidos", "res": "Carnes y embutidos",
    "cerdo": "Carnes y embutidos", "pollo": "Carnes y embutidos",
    "pescad": "Carnes y embutidos", "atun": "Carnes y embutidos",
    "sardina": "Carnes y embutidos", "embutid": "Carnes y embutidos",
    "salchicha": "Carnes y embutidos", "jamon": "Carnes y embutidos",
    "mortadela": "Carnes y embutidos", "delikatessen": "Carnes y embutidos",
    # congelados
    "congelad": "Congelados",
    # frutas y verduras
    "fruta": "Frutas y verduras", "verdur": "Frutas y verduras",
    "hortaliz": "Frutas y verduras", "tuberculo": "Frutas y verduras",
    "papa": "Frutas y verduras", "yuca": "Frutas y verduras",
    "platano": "Frutas y verduras", "legumbr": "Frutas y verduras",
    "frutas y verduras": "Frutas y verduras",
    # snacks
    "snack": "Snacks", "pasaboca": "Snacks", "mecato": "Snacks",
    "papas fritas": "Snacks",
    # aseo del hogar (incluye el stem "hogar" -- ver nota en PALABRAS_INCLUSION)
    "hogar": "Aseo del hogar", "aseo": "Aseo del hogar",
    "papel higienico": "Aseo del hogar", "papel de cocina": "Aseo del hogar",
    "servilleta": "Aseo del hogar", "detergente": "Aseo del hogar",
    "suavizante": "Aseo del hogar", "jabon": "Aseo del hogar",
    "lavaloza": "Aseo del hogar", "limpi": "Aseo del hogar",
    "desinfect": "Aseo del hogar", "bolsas de basura": "Aseo del hogar",
    "bolsa basura": "Aseo del hogar", "esponja": "Aseo del hogar",
    "escoba": "Aseo del hogar", "trapero": "Aseo del hogar",
    "ambientador": "Aseo del hogar", "blanqueador": "Aseo del hogar",
    # cuidado personal
    "cuidado personal": "Cuidado personal", "higiene personal": "Cuidado personal",
    "shampoo": "Cuidado personal", "champu": "Cuidado personal",
    "crema dental": "Cuidado personal", "cepillo dental": "Cuidado personal",
    "desodorante": "Cuidado personal",
}


def etiqueta_amigable(texto: str | None) -> str | None:
    """Etiqueta de categoría legible para el consumidor (ej. "Frutas y
    verduras"), o None si el texto no coincide con ninguna palabra de
    inclusión -- en ese caso NUNCA se debe mostrar la ruta cruda como
    respaldo, es preferible omitir el campo."""
    bucket = obtener_bucket(texto)
    if bucket is None:
        return None
    return ETIQUETAS_AMIGABLES.get(bucket)


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
