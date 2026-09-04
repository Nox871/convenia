import asyncio
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import (
    urljoin,
    urlparse,
    parse_qs,
    urlencode,
    urlunparse,
)
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from crawl4ai import (
    AsyncWebCrawler,
    BrowserConfig,
    CrawlerRunConfig,
    CacheMode,
)

# scraper/connectors/d1/scraper.py -> parents[2] = scraper/
_SCRAPER_ROOT = Path(__file__).resolve().parents[2]
if str(_SCRAPER_ROOT) not in sys.path:
    sys.path.insert(0, str(_SCRAPER_ROOT))

from core.category_filter import clasificar_categoria  # noqa: E402


# ============================================================
# CONFIGURACIÓN
# ============================================================

SOURCE = "D1"
DOMINIO_BASE = "https://www.d1.com.co"

MAX_CATEGORIAS = 10
MAX_PAGINAS_POR_CATEGORIA = 1  # TEMP: reducido solo para validación, revertir a 4

DELAY_ENTRE_PAGINAS = 0.50
DELAY_ENTRE_PRODUCTOS = 0.20

MAX_REINTENTOS = 3

PRODUCT_PAGE_TIMEOUT = 120000

# Crawl4AI
MAX_SCROLLS = 20


# ============================================================
# ZONA HORARIA
# ============================================================

try:
    TIMEZONE = ZoneInfo("America/Bogota")
except ZoneInfoNotFoundError:
    raise RuntimeError(
        "No se encontró la zona horaria 'America/Bogota'. "
        "Instala tzdata dentro del entorno virtual con:\n\n"
        "pip install tzdata"
    )


# ============================================================
# RUTAS
# ============================================================

# scraper/connectors/d1/scraper.py
#
# parents:
#   d1 -> connectors
#   connectors -> scraper
#   scraper -> prezio
#
# parents[3] = E:\prezio

BASE_PROYECTO = Path(__file__).resolve().parents[3]

RUTA_RAW = BASE_PROYECTO / "data" / "raw" / "d1" / "productos"
RUTA_RAW_JSON = RUTA_RAW / "d1_raw.json"
RUTA_DEBUG = BASE_PROYECTO / "data" / "raw" / "d1" / "debug"


# ============================================================
# HEADERS
# ============================================================

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/151.0.0.0 Safari/537.36"
)


# ============================================================
# FILTROS DE URL
# ============================================================

PATRONES_OMITIR = re.compile(
    r"""
    (
        cuenta | carrito | checkout | login | autenticacion |
        autorizacion | ayuda | legal | terminos | condiciones |
        politica | privacidad | institucional | blog | contacto |
        trabaja | puntos | referidos | nosotros | sostenibilidad |
        proveedores | tiendas | servicio-al-cliente |
        preguntas-frecuentes
    )
    """,
    re.IGNORECASE | re.VERBOSE,
)

HOSTS_D1 = {"d1.com.co", "www.d1.com.co"}


# ============================================================
# CATEGORÍAS CONOCIDAS
# ============================================================

CATEGORIAS_PRINCIPALES = {
    "/despensa",
    "/bebidas",
    "/hogar",
    "/cuidado-personal-y-belleza",
    "/frutas-y-verduras",
    "/lacteos-y-huevos",
    "/congelados",
    "/aseo-y-limpieza",
    "/carnes-frias-delikatessen",
    "/extraordinarios",
}

# Prefijos para subcategorías (p. ej. /despensa/enlatados-y-envasados).
PREFIJOS_CATEGORIA = tuple(
    f"{ruta}/" for ruta in CATEGORIAS_PRINCIPALES
)


# ============================================================
# UTILIDADES GENÉRICAS
# ============================================================

def obtener_timestamp_actual():
    return datetime.now(TIMEZONE).isoformat(timespec="seconds")


def esta_vacio(valor):
    """True si el valor debe considerarse ausente."""
    return valor in (None, "", [])


def completar_campos_vacios(destino, origen):
    """Rellena en 'destino' los campos vacíos usando 'origen'."""
    for campo, valor in origen.items():
        if esta_vacio(destino.get(campo)) and not esta_vacio(valor):
            destino[campo] = valor


def asignar_si_presente(producto, campo, valor):
    """Asigna 'valor' a 'campo' solo si el valor no está vacío."""
    if not esta_vacio(valor):
        producto[campo] = valor


def limpiar_texto(valor):
    if valor is None:
        return ""

    texto = str(valor).replace("\xa0", " ")
    texto = re.sub(r"\s+", " ", texto)
    return texto.strip()


def convertir_numero(valor):
    if valor is None or isinstance(valor, bool):
        return None

    if isinstance(valor, (int, float)):
        return float(valor)

    texto = re.sub(r"[^\d,.\-]", "", limpiar_texto(valor))
    if not texto:
        return None

    tiene_punto = "." in texto
    tiene_coma = "," in texto

    # 12.990 (punto como separador de miles)
    if tiene_punto and not tiene_coma:
        partes = texto.split(".")
        if len(partes) > 1 and all(len(p) == 3 for p in partes[1:]):
            texto = "".join(partes)

    # 12,990 (coma miles) vs 12,99 (coma decimal)
    elif tiene_coma and not tiene_punto:
        partes = texto.split(",")
        if len(partes) > 1 and all(len(p) == 3 for p in partes[1:]):
            texto = "".join(partes)
        else:
            texto = texto.replace(",", ".")

    # 3.859,50
    elif tiene_punto and tiene_coma:
        if texto.rfind(",") > texto.rfind("."):
            texto = texto.replace(".", "").replace(",", ".")
        else:
            texto = texto.replace(",", "")

    try:
        return float(texto)
    except ValueError:
        return None


# ============================================================
# URL
# ============================================================

def _reconstruir_url(scheme, netloc, path):
    return urlunparse((scheme.lower(), netloc.lower(), path, "", "", ""))


def _parsear_con_dominio(url):
    parsed = urlparse(str(url).strip())
    if not parsed.scheme:
        parsed = urlparse(urljoin(DOMINIO_BASE, str(url).strip()))
    return parsed


def normalizar_url(url):
    if not url:
        return ""

    parsed = _parsear_con_dominio(url)
    return _reconstruir_url(parsed.scheme, parsed.netloc, parsed.path)


def normalizar_product_url(url):
    if not url:
        return None

    parsed = _parsear_con_dominio(url)

    if parsed.netloc.lower() not in HOSTS_D1:
        return None

    return _reconstruir_url("https", "www.d1.com.co", parsed.path)


def es_producto_url(url):
    if not url:
        return False

    path = urlparse(url).path.rstrip("/").lower()
    return path.endswith("/p")


def es_url_comercial(url):
    try:
        parsed = urlparse(url)

        if parsed.netloc.lower() not in HOSTS_D1:
            return False

        path = parsed.path.rstrip("/").lower()

        if not path or path.endswith("/p"):
            return False

        if re.search(
            r"\.(pdf|jpg|jpeg|png|gif|webp|svg|xml|json|css|js)$",
            path,
            re.IGNORECASE,
        ):
            return False

        if PATRONES_OMITIR.search(path):
            return False

        if path.startswith("/api/") or path.startswith("/_next/"):
            return False

        return True

    except Exception:
        return False


def es_categoria_valida(url):
    """
    Válida si:
      1. Tiene la forma de una categoría real de D1 (top-level conocida o
         subcategoría bajo una de ellas), Y
      2. Su nombre (derivado de la URL) pertenece al alcance de canasta
         familiar según el clasificador por palabras clave
         (`core.category_filter`) -- esto es lo que descarta, por ejemplo,
         "Extraordinarios" (bazar/misceláneos) sin tener que mantener una
         lista rígida de subcategorías excluidas.
    """
    if not es_url_comercial(url):
        return False

    path = urlparse(url).path.rstrip("/").lower()

    es_forma_de_categoria = path in CATEGORIAS_PRINCIPALES or path.startswith(
        PREFIJOS_CATEGORIA
    )
    if not es_forma_de_categoria:
        return False

    nombre = categoria_desde_url(url)
    return clasificar_categoria(nombre)[0]


def construir_url_pagina_categoria(categoria_url, pagina):
    parsed = urlparse(categoria_url)
    query = parse_qs(parsed.query, keep_blank_values=True)
    query["page"] = [str(pagina)]

    return urlunparse(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            parsed.params,
            urlencode(query, doseq=True),
            parsed.fragment,
        )
    )


def categoria_desde_url(categoria_url):
    """
    Deriva una categoría legible a partir de la propia URL de categoría.

    Es determinista y siempre está presente (a diferencia de leer el
    breadcrumb del PDP, que es frágil):

        /extraordinarios                     -> "Extraordinarios"
        /despensa/granos-azucar-y-panela     -> "Granos azucar y panela"
    """
    path = urlparse(categoria_url).path.rstrip("/").lower()
    if not path:
        return None

    segmento = path.split("/")[-1].replace("-", " ").strip()
    return segmento.capitalize() if segmento else None


def plu_desde_url(url):
    """
    El slug del producto termina en el PLU:

        /encendedor-yama-12005443/p  ->  "12005443"
    """
    if not url:
        return None

    path = urlparse(url).path.rstrip("/")
    match = re.search(r"-(\d{5,})/p$", path, re.IGNORECASE)
    return match.group(1) if match else None


# ============================================================
# EXTRACCIÓN DESDE MARKDOWN (PDP)
# ============================================================

def _lineas_limpias(markdown):
    return [limpiar_texto(linea) for linea in (markdown or "").splitlines()]


def extraer_plu(texto):
    if not texto:
        return None

    match = re.search(r"\bPLU\s*[:#]?\s*(\d{5,})\b", texto, re.IGNORECASE)
    return match.group(1) if match else None


def extraer_precio_d1(texto):
    if not texto:
        return None

    # \s ya cubre el espacio no separable (\xa0), así que un patrón basta.
    match = re.search(r"\$\s*([\d.,]+)", texto)
    if not match:
        return None

    return convertir_numero(match.group(1))


def extraer_nombre_pdp(markdown):
    for linea in _lineas_limpias(markdown):
        if linea.startswith("# "):
            nombre = limpiar_texto(linea[2:])
            if nombre:
                return nombre
    return None


def extraer_marca_pdp(markdown):
    """
    Heurística: en el PDP de D1 la línea inmediatamente anterior al
    título (encabezado '# ') suele ser la MARCA (p. ej. "YAMA",
    "RED FLAG"), no la categoría.

    Antes esta función alimentaba 'category', lo que producía
    category="YAMA". Ahora alimenta 'brand'.

    La fuente fiable de marca/categoría es el catálogo VTEX (ver nota
    al final del archivo).
    """
    lineas = _lineas_limpias(markdown)

    for indice, linea in enumerate(lineas):
        if linea.startswith("# ") and indice > 0:
            anteriores = [
                l for l in lineas[max(0, indice - 5):indice] if l
            ]
            if anteriores:
                return anteriores[-1]

    return None


def extraer_imagen_desde_markdown(markdown):
    if not markdown:
        return None

    # ![alt](https://...)
    match = re.search(r"!\[[^\]]*\]\(([^)]+)\)", markdown, re.IGNORECASE)
    if match:
        return limpiar_texto(match.group(1))

    # Fallback: cualquier URL de imagen visible.
    match = re.search(
        r"https?://[^\s)\"']+\.(?:jpg|jpeg|png|webp)",
        markdown,
        re.IGNORECASE,
    )
    return match.group(0) if match else None


# ============================================================
# PRODUCTO
# ============================================================

def crear_producto_base(product_url, categoria_url, pagina, extracted_at, nombre):
    return {
        "source": SOURCE,
        "product_id": None,
        "product_name": nombre or None,
        "brand": None,
        "brand_id": None,
        "product_reference": None,
        "product_reference_code": None,
        "category_id": None,
        "category": categoria_desde_url(categoria_url),
        "price": None,
        "list_price": None,
        "currency": "COP",
        "image_url": None,
        "product_url": product_url,
        "source_category_url": categoria_url,
        "page": pagina,
        "release_date": None,
        "seller_id": None,
        "seller_name": "D1",
        "seller_available_quantity": None,
        "payment_methods": [],
        "extracted_at": extracted_at,
    }


def extraer_productos_categoria(resultado, categoria_url, pagina, extracted_at):
    productos = []

    if resultado is None:
        return productos

    vistos = set()

    for enlace in resultado.links.get("internal", []):
        href = enlace.get("href", "")
        if not href:
            continue

        product_url = normalizar_product_url(href)
        if not product_url or not es_producto_url(product_url):
            continue

        if product_url in vistos:
            continue
        vistos.add(product_url)

        nombre = limpiar_texto(enlace.get("text", ""))

        productos.append(
            crear_producto_base(
                product_url,
                categoria_url,
                pagina,
                extracted_at,
                nombre,
            )
        )

    return productos


# ============================================================
# CRAWL4AI
# ============================================================

def crear_configuracion_crawler():
    return CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        page_timeout=PRODUCT_PAGE_TIMEOUT,
        delay_before_return_html=3,
        wait_for="css:body",
        magic=True,
        simulate_user=True,
        override_navigator=True,
    )


class Reintentar(Exception):
    """Señal para forzar otro intento dentro de con_reintentos()."""


async def con_reintentos(operacion, *, backoff=1.0, max_intentos=MAX_REINTENTOS):
    """
    Ejecuta la corrutina 'operacion' reintentando ante fallos.

    'operacion' devuelve el resultado en caso de éxito o lanza
    Reintentar(mensaje) / cualquier excepción para forzar otro intento.

    Devuelve (resultado, None) o (None, ultimo_error).
    """
    ultimo_error = None

    for intento in range(1, max_intentos + 1):
        try:
            return await operacion(), None
        except Exception as exc:
            ultimo_error = str(exc)

        if intento < max_intentos:
            await asyncio.sleep(intento * backoff)

    return None, ultimo_error


async def obtener_pagina(crawler, url):
    config = crear_configuracion_crawler()

    async def operacion():
        resultado = await crawler.arun(url=url, config=config)
        if not resultado.success:
            raise Reintentar(resultado.error_message)
        return resultado

    resultado, error = await con_reintentos(operacion, backoff=1.0)

    if error is not None:
        print("[CRAWL] Error al cargar:")
        print(f"        {url}")
        print(f"        {error}")
        return None

    return resultado


# ============================================================
# DESCUBRIR CATEGORÍAS
# ============================================================

ESTADISTICAS_CATEGORIAS = {"encontradas": 0, "aceptadas": 0, "descartadas": 0}


async def descubrir_categorias(crawler):
    print()
    print("=" * 60)
    print("[FASE 1] DESCUBRIENDO CATEGORÍAS D1")
    print("=" * 60)

    resultado = await obtener_pagina(crawler, DOMINIO_BASE)
    if resultado is None:
        return []

    candidatas = []
    vistas = set()

    for enlace in resultado.links.get("internal", []):
        href = enlace.get("href", "")
        if not href:
            continue

        url = normalizar_url(href)

        if not es_url_comercial(url) or url in vistas:
            continue

        vistas.add(url)
        candidatas.append(url)

    aceptadas = []
    descartadas = []

    for url in candidatas:
        path = urlparse(url).path.rstrip("/").lower()
        es_forma_de_categoria = path in CATEGORIAS_PRINCIPALES or path.startswith(
            PREFIJOS_CATEGORIA
        )

        if not es_forma_de_categoria:
            continue  # ni siquiera tiene forma de categoría de D1; se ignora del reporte

        if es_categoria_valida(url):
            aceptadas.append(url)
        else:
            _, motivo = clasificar_categoria(categoria_desde_url(url))
            descartadas.append((url, motivo))

    # Preferir categorías principales para no terminar procesando solo
    # subcategorías si el homepage trae muchas.
    def es_principal(categoria):
        return urlparse(categoria).path.rstrip("/").count("/") == 1

    aceptadas.sort(key=lambda c: 0 if es_principal(c) else 1)

    print(f"[FASE 1] Candidatas con forma de categoría: {len(aceptadas) + len(descartadas)}")
    print(f"[FASE 1] Categorías aceptadas (canasta familiar): {len(aceptadas)}")
    for indice, categoria in enumerate(aceptadas, start=1):
        print(f"  [OK]  [{indice}] {categoria}")
    print(f"[FASE 1] Categorías descartadas: {len(descartadas)}")
    for url, motivo in descartadas:
        print(f"  [--]  {url}  ({motivo})")

    categorias = aceptadas[:MAX_CATEGORIAS]

    ESTADISTICAS_CATEGORIAS["encontradas"] = len(aceptadas) + len(descartadas)
    ESTADISTICAS_CATEGORIAS["aceptadas"] = len(categorias)
    ESTADISTICAS_CATEGORIAS["descartadas"] = len(descartadas) + (
        len(aceptadas) - len(categorias)
    )

    print()
    print(f"[FASE 1] Se procesarán {len(categorias)} categorías.")

    return categorias


# ============================================================
# ENRIQUECER PDP
# ============================================================

async def enriquecer_producto(crawler, producto):
    product_url = producto.get("product_url")
    if not product_url:
        return producto

    print(f"[PDP] {producto.get('product_name', '')}")

    resultado = await obtener_pagina(crawler, product_url)
    if resultado is None:
        return producto

    markdown = getattr(resultado, "markdown", "")
    if not isinstance(markdown, str):
        markdown = ""

    # PLU: primero desde el markdown; si no aparece, desde la URL.
    plu = extraer_plu(markdown) or plu_desde_url(product_url)
    if plu:
        producto["product_id"] = plu
        producto["product_reference"] = plu
        producto["product_reference_code"] = plu

    asignar_si_presente(producto, "product_name", extraer_nombre_pdp(markdown))
    asignar_si_presente(producto, "price", extraer_precio_d1(markdown))
    asignar_si_presente(producto, "brand", extraer_marca_pdp(markdown))
    asignar_si_presente(
        producto, "image_url", extraer_imagen_desde_markdown(markdown)
    )

    # NOTA sobre métodos de pago:
    # No copiamos el sistema de Éxito. Aún hay que comprobar si D1
    # muestra métodos/promos en el PDP. Por ahora se deja [].

    print(
        f"[PDP] PLU={producto.get('product_id')} "
        f"| Precio={producto.get('price')} "
        f"| Marca={producto.get('brand')} "
        f"| Categoría={producto.get('category')}"
    )

    await asyncio.sleep(DELAY_ENTRE_PRODUCTOS)

    return producto


# ============================================================
# DEDUPLICACIÓN
# ============================================================

def deduplicar_productos(productos):
    unicos = {}

    for producto in productos:
        product_id = producto.get("product_id")

        # Si todavía no tenemos PLU, usamos la URL como clave provisional.
        clave = (
            f"PLU:{product_id}"
            if product_id
            else f"URL:{producto.get('product_url')}"
        )

        existente = unicos.get(clave)

        if existente is None:
            unicos[clave] = producto
        else:
            completar_campos_vacios(existente, producto)

    return list(unicos.values())


# ============================================================
# CALIDAD
# ============================================================

CAMPOS_CALIDAD = [
    "product_id",
    "product_name",
    "brand",
    "category",
    "price",
    "currency",
    "image_url",
    "product_url",
    "seller_name",
    "extracted_at",
]


def imprimir_calidad(productos):
    print()
    print("=" * 60)
    print("[CALIDAD DE DATOS]")
    print("=" * 60)

    total = len(productos)
    if total == 0:
        print("Sin productos para evaluar.")
        return

    for campo in CAMPOS_CALIDAD:
        faltantes = sum(
            1 for producto in productos if esta_vacio(producto.get(campo))
        )
        presentes = total - faltantes
        porcentaje = (presentes / total) * 100

        print(
            f"  {campo:<28}{presentes:>4}/{total:<4}"
            f" ({porcentaje:>6.2f}%)"
        )


# ============================================================
# PROCESAR CATEGORÍA
# ============================================================

async def procesar_categoria(
    crawler,
    categoria_url,
    categoria_index,
    total_categorias,
):
    print()
    print("=" * 60)
    print(f"[CATEGORÍA {categoria_index}/{total_categorias}]")
    print("=" * 60)
    print(categoria_url)

    productos_categoria = []

    for pagina in range(1, MAX_PAGINAS_POR_CATEGORIA + 1):
        pagina_url = construir_url_pagina_categoria(categoria_url, pagina)

        print()
        print("-" * 60)
        print(f"[PÁGINA {pagina}]")
        print(f"URL: {pagina_url}")
        print("-" * 60)

        inicio = time.perf_counter()
        resultado = await obtener_pagina(crawler, pagina_url)
        duracion = time.perf_counter() - inicio

        if resultado is None:
            print("[PÁGINA] No se pudo cargar.")
            break

        extracted_at = obtener_timestamp_actual()

        productos = extraer_productos_categoria(
            resultado, categoria_url, pagina, extracted_at
        )

        print(
            f"[CATEGORÍA] PDP encontrados: {len(productos)} | {duracion:.2f}s"
        )

        if not productos:
            print("[PAGINACIÓN] No se encontraron productos.")
            break

        for producto in productos:
            await enriquecer_producto(crawler, producto)

        productos_categoria.extend(productos)

        if pagina >= MAX_PAGINAS_POR_CATEGORIA:
            break

        await asyncio.sleep(DELAY_ENTRE_PAGINAS)

    productos_categoria = deduplicar_productos(productos_categoria)

    print()
    print(f"[CATEGORÍA] Productos únicos: {len(productos_categoria)}")

    return productos_categoria


# ============================================================
# GUARDAR RAW
# ============================================================

def guardar_raw(
    productos,
    categorias_procesadas,
    extraction_started_at,
    extraction_finished_at,
):
    RUTA_RAW.mkdir(parents=True, exist_ok=True)

    payload = {
        "source": SOURCE,
        "start_url": DOMINIO_BASE,
        "extraction_started_at": extraction_started_at,
        "extraction_finished_at": extraction_finished_at,
        "timezone": "America/Bogota",
        "categories_processed": categorias_procesadas,
        "max_categories": MAX_CATEGORIAS,
        "max_pages_per_category": MAX_PAGINAS_POR_CATEGORIA,
        "products_found": len(productos),
        "products_unique": len(productos),
        "products": productos,
    }

    with open(RUTA_RAW_JSON, "w", encoding="utf-8") as archivo:
        json.dump(payload, archivo, ensure_ascii=False, indent=2)

    return payload


# ============================================================
# MAIN
# ============================================================

async def main():
    extraction_started_at = obtener_timestamp_actual()

    print()
    print("=" * 60)
    print("PREZIO - SCRAPER D1")
    print("=" * 60)
    print(f"Inicio extracción: {extraction_started_at}")
    print(f"URL inicial: {DOMINIO_BASE}")
    print(f"Máximo categorías: {MAX_CATEGORIAS}")
    print(f"Máximo páginas/categoría: {MAX_PAGINAS_POR_CATEGORIA}")
    print("Catálogo: PÁGINAS D1 + PDP")
    print("Zona horaria: America/Bogota")
    print()

    browser_config = BrowserConfig(
        headless=True,
        verbose=False,
        user_agent=USER_AGENT,
    )

    async with AsyncWebCrawler(config=browser_config) as crawler:
        # FASE 1
        categorias = await descubrir_categorias(crawler)

        if not categorias:
            print()
            print("[ERROR] No se encontraron categorías válidas.")
            return

        # FASE 2
        productos_totales = []

        for indice, categoria_url in enumerate(categorias, start=1):
            productos_categoria = await procesar_categoria(
                crawler,
                categoria_url,
                indice,
                len(categorias),
            )
            productos_totales.extend(productos_categoria)

        # DEDUPLICACIÓN GLOBAL
        productos_totales = deduplicar_productos(productos_totales)

        extraction_finished_at = obtener_timestamp_actual()

        # RESUMEN
        print()
        print("=" * 60)
        print("[RAW]")
        print("=" * 60)
        print(f"Inicio extracción: {extraction_started_at}")
        print(f"Fin extracción:    {extraction_finished_at}")
        print(f"Categorías procesadas: {len(categorias)}")
        print(f"Registros encontrados: {len(productos_totales)}")
        print(f"Registros únicos: {len(productos_totales)}")

        imprimir_calidad(productos_totales)

        guardar_raw(
            productos_totales,
            len(categorias),
            extraction_started_at,
            extraction_finished_at,
        )

        print()
        print("=" * 60)
        print("[REPORTE CANASTA FAMILIAR]")
        print("=" * 60)
        print("D1:")
        print(f"  Categorías encontradas:  {ESTADISTICAS_CATEGORIAS['encontradas']}")
        print(f"  Categorías aceptadas:    {ESTADISTICAS_CATEGORIAS['aceptadas']}")
        print(f"  Categorías descartadas:  {ESTADISTICAS_CATEGORIAS['descartadas']}")
        print(f"  Productos obtenidos:     {len(productos_totales)}")

        print()
        print(f"Archivo: {RUTA_RAW_JSON}")
        print()
        print("=" * 60)
        print("[FIN]")
        print("=" * 60)


# ============================================================
# EJECUCIÓN
# ============================================================

if __name__ == "__main__":
    asyncio.run(main())