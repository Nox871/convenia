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

import httpx

from crawl4ai import (
    AsyncWebCrawler,
    BrowserConfig,
    CrawlerRunConfig,
    CacheMode,
)

# scraper/connectors/exito/scraper.py -> parents[2] = scraper/
_SCRAPER_ROOT = Path(__file__).resolve().parents[2]
if str(_SCRAPER_ROOT) not in sys.path:
    sys.path.insert(0, str(_SCRAPER_ROOT))

from core.category_filter import clasificar_categoria, factor_paginas  # noqa: E402
from core.raw_writer import guardar_raw_snapshot  # noqa: E402


# ============================================================
# CONFIGURACIÓN
# ============================================================

SOURCE = "EXITO"
DOMINIO_BASE = "https://www.exito.com"

MAX_CATEGORIAS = 10
MAX_PAGINAS_POR_CATEGORIA = 4

# VTEX permite hasta 50 productos por petición.
PRODUCTOS_POR_PETICION = 50

CONCURRENCIA = 3

# Crawl4AI
MAX_SCROLLS = 40

# Tiempo entre peticiones VTEX.
DELAY_ENTRE_PETICIONES = 0.20

# Tiempo entre páginas de producto.
DELAY_ENTRE_PRODUCTOS = 0.10

# Reintentos HTTP.
MAX_REINTENTOS = 3

# Timeout HTTP.
HTTP_TIMEOUT = 60.0

# Timeout para páginas de producto.
PRODUCT_PAGE_TIMEOUT = 120000


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

# scraper/connectors/exito/scraper.py
#
# parents:
#   exito -> connectors
#   connectors -> scraper
#   scraper -> prezio
#
# parents[3] = E:\prezio

BASE_PROYECTO = Path(__file__).resolve().parents[3]

RUTA_RAW = BASE_PROYECTO / "data" / "raw" / "exito" / "productos"
RUTA_RAW_JSON = RUTA_RAW / "exito_raw.json"
RUTA_DEBUG = BASE_PROYECTO / "data" / "raw" / "exito" / "debug"


# ============================================================
# ENDPOINT VTEX
# ============================================================

VTEX_SEARCH_ENDPOINT = (
    f"{DOMINIO_BASE}/api/catalog_system/pub/products/search"
)


# ============================================================
# HEADERS
# ============================================================

HEADERS = {
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "es-CO,es;q=0.9,en;q=0.8",
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/151.0.0.0 Safari/537.36"
    ),
    "Referer": f"{DOMINIO_BASE}/",
    "Connection": "keep-alive",
}


# ============================================================
# FILTROS DE URL
# ============================================================

PATRONES_OMITIR = re.compile(
    r"""
    (
        cuenta | carrito | checkout | login | authentication |
        autorizacion | ayuda | legal | terminos | condiciones |
        politica | privacidad | institucional | blog | contacto |
        trabaja | puntos | denuncias | referidos | actualizate |
        datos-compania | sitemap | vendedores | marketplace |
        garantia | habeas | fale-conosco | atendimento | sac
    )
    """,
    re.IGNORECASE | re.VERBOSE,
)

# Hosts que consideramos equivalentes a www.exito.com.
HOSTS_EXITO = {
    "tienda.exito.com",
    "exito.com",
    "www.exito.com",
}


# ============================================================
# MÉTODOS DE PAGO VÁLIDOS
# ============================================================
#
# IMPORTANTE:
#
# Esta lista funciona como una LISTA BLANCA.
#
# Cualquier texto que NO esté aquí NO será considerado
# método de pago.
#
# Por tanto:
#
#   Carrito      -> NO
#   Menu         -> NO
#   1 Opinión    -> NO
#   Comprar      -> NO
#   Agregar      -> NO
#
# Mientras que:
#
#   exito        -> SÍ
#   mastercard   -> SÍ
#   visa         -> SÍ
#   Otros        -> SÍ
#
# Se pueden agregar nuevos métodos aquí si Éxito incorpora
# otros medios legítimos.

METODOS_PAGO_VALIDOS = {
    "exito": "exito",
    "éxito": "exito",
    "mastercard": "mastercard",
    "master card": "mastercard",
    "visa": "visa",
    "american express": "american express",
    "amex": "american express",
    "diners": "diners",
    "diners club": "diners",
    "bbva": "bbva",
    "bancolombia": "bancolombia",
    "pse": "pse",
    "nequi": "nequi",
    "daviplata": "daviplata",
    "codensa": "codensa",
    "tuya": "tuya",
    "falabella": "falabella",
    "otros": "Otros",
}


# ============================================================
# TEXTOS QUE JAMÁS DEBEN SER MÉTODOS DE PAGO
# ============================================================

METODOS_PAGO_INVALIDOS = {
    "carrito",
    "menu",
    "menú",
    "comprar",
    "comprar ahora",
    "agregar",
    "agregar al carrito",
    "opinión",
    "opinion",
    "1 opinión",
    "2 opiniones",
    "3 opiniones",
    "ver términos y condiciones",
    "términos y condiciones",
    "terminos y condiciones",
    "ofertas adicionales",
    "últimas unidades",
    "ultimas unidades",
    "enviado por",
    "vendido por",
    "tiempo de entrega",
    "garantía del producto",
    "garantia del producto",
}


# ============================================================
# UTILIDADES GENÉRICAS
# ============================================================

def obtener_timestamp_actual():
    return datetime.now(TIMEZONE).isoformat(timespec="seconds")


def esta_vacio(valor):
    """True si el valor debe considerarse ausente."""
    return valor in (None, "", [])


def a_str(valor):
    """Convierte a str conservando None."""
    return None if valor is None else str(valor)


def primer_valor(dic, *claves, default=None):
    """
    Devuelve el primer valor no nulo entre varias claves posibles.

    Reemplaza el patrón repetido:

        offer.get("Price") if offer.get("Price") is not None
        else offer.get("price")
    """
    if not isinstance(dic, dict):
        return default

    for clave in claves:
        valor = dic.get(clave)
        if valor is not None:
            return valor

    return default


def completar_campos_vacios(destino, origen):
    """Rellena en 'destino' los campos vacíos usando 'origen'."""
    for campo, valor in origen.items():
        if esta_vacio(destino.get(campo)) and not esta_vacio(valor):
            destino[campo] = valor


def limpiar_texto(valor):
    if valor is None:
        return ""

    texto = str(valor).replace("\xa0", " ")
    texto = re.sub(r"\s+", " ", texto)
    return texto.strip()


def convertir_numero(valor):
    """
    Convierte valores numéricos colombianos.

    Ejemplos:
        12990
        "12990"
        "12.990"
        "12,990"
        "3.859,50"
    """
    if valor is None or isinstance(valor, bool):
        return None

    if isinstance(valor, (int, float)):
        return float(valor)

    texto = re.sub(r"[^\d,.\-]", "", limpiar_texto(valor))
    if not texto:
        return None

    tiene_punto = "." in texto
    tiene_coma = "," in texto

    # 12.990 / 3.859.500  (el punto es separador de miles)
    if tiene_punto and not tiene_coma:
        partes = texto.split(".")
        if len(partes) > 1 and all(len(p) == 3 for p in partes[1:]):
            texto = "".join(partes)

    # 12,990 (coma como miles) vs 12,99 (coma como decimal)
    elif tiene_coma and not tiene_punto:
        partes = texto.split(",")
        if len(partes) > 1 and all(len(p) == 3 for p in partes[1:]):
            texto = "".join(partes)
        else:
            texto = texto.replace(",", ".")

    # 3.859,50 (punto miles, coma decimal) o al revés
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
# NORMALIZACIÓN DE URL
# ============================================================

def _reconstruir_url(scheme, netloc, path):
    """Reconstruye una URL sin query, params ni fragment."""
    return urlunparse(
        (scheme.lower(), netloc.lower(), path, "", "", "")
    )


def _parsear_con_dominio(url):
    """Parsea una URL asegurando esquema absoluto contra DOMINIO_BASE."""
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

    if parsed.netloc.lower() not in HOSTS_EXITO:
        return None

    return _reconstruir_url(parsed.scheme, "www.exito.com", parsed.path)


def es_producto_url(url):
    if not url:
        return False

    path = urlparse(url).path.rstrip("/").lower()
    return path.endswith("/p")


def es_url_comercial(url):
    try:
        parsed = urlparse(url)

        if parsed.netloc.lower() != "www.exito.com":
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

        if path.startswith("/_next/") or path.startswith("/api/"):
            return False

        return True

    except Exception:
        return False



# ============================================================
# ALCANCE DEL PROYECTO: CANASTA FAMILIAR
# ============================================================
#
# Éxito expone su catálogo bajo verticales muy distintas (tecnología,
# vinos, moda, electrodomésticos, deportes, ferretería, ...) además de la
# vertical de supermercado propiamente dicha (/mercado/...). Convenia solo
# necesita esta última.
#
# IMPORTANTE: se descarta deliberadamente `/coleccion/<id>` (colecciones
# VTEX numéricas, usadas por Éxito para banners/destacados de la home).
# No tienen nombre legible en la URL -- son la causa por la que antes
# entraban categorías como "Tecnología" o "Vinos y licores": el número no
# dice nada sobre el contenido real hasta después de scrapear productos.
#
# Dentro de `/mercado/...` se aplica además el clasificador por palabras
# clave (`core.category_filter`), porque esa vertical también mezcla
# subcategorías fuera de alcance (p. ej. "mundo-del-bebe" si apareciera
# ahí, bazar, etc.).

PREFIJO_MERCADO = "/mercado/"

# Estadísticas de la fase de descubrimiento, para el reporte final de main().
ESTADISTICAS_CATEGORIAS = {"encontradas": 0, "aceptadas": 0, "descartadas": 0}


def es_categoria_valida(url):
    if not es_url_comercial(url):
        return False

    path = urlparse(url).path.rstrip("/").lower()

    if not path.startswith(PREFIJO_MERCADO):
        return False

    segmento = path[len(PREFIJO_MERCADO):]
    if segmento in ("home", "donacion-mercados"):
        return False

    texto = segmento.replace("-", " ").replace("/", " ")
    return clasificar_categoria(texto)[0]


# ============================================================
# CATEGORÍAS
# ============================================================

def extraer_id_coleccion(url):
    match = re.search(
        r"/coleccion/(\d+)", urlparse(url).path, re.IGNORECASE
    )
    return match.group(1) if match else None


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


# ============================================================
# FASE 1 - DESCUBRIR CATEGORÍAS
# ============================================================

def _config_descubrimiento():
    return CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        wait_for="css:body",
        delay_before_return_html=3,
        page_timeout=120000,
        magic=True,
        simulate_user=True,
        override_navigator=True,
    )


def _extraer_urls_comerciales(resultado, base_url):
    """Todas las URLs comerciales (no solo de categoría) de una página, en
    orden de aparición, sin duplicados."""
    urls = []
    vistas = set()

    for enlace in resultado.links.get("internal", []):
        href = enlace.get("href", "")
        if not href:
            continue

        url = normalizar_url(urljoin(base_url, href))
        if not es_url_comercial(url) or url in vistas:
            continue

        vistas.add(url)
        urls.append(url)

    return urls


async def _extraer_hub_con_reintento(crawler, hub_url, base_url, prefijo_esperado,
                                      minimo_esperado=5, intentos=3):
    """Crawlea `hub_url` y extrae sus URLs comerciales, reintentando con más
    tiempo de espera si trae muy pocos enlaces bajo `prefijo_esperado`.

    El mega-menú de algunos sitios VTEX carga de forma diferida (lazy) y no
    siempre termina de renderizar dentro del tiempo de espera por defecto:
    la MISMA URL puede devolver 3 subcategorías en una corrida y 7 en la
    siguiente (verificado en Olímpica; se aplica el mismo resguardo aquí
    por si acaso). No es un problema de la lógica de validación de URLs,
    sino de cuánto tarda en cargar la página.
    """
    mejor_urls: list[str] = []

    for intento in range(1, intentos + 1):
        espera = 3 + (intento - 1) * 5  # 3s, 8s, 13s...
        config = CrawlerRunConfig(
            cache_mode=CacheMode.BYPASS,
            wait_for="css:body",
            delay_before_return_html=espera,
            page_timeout=120000,
            magic=True,
            simulate_user=True,
            override_navigator=True,
        )

        resultado = await crawler.arun(url=hub_url, config=config)
        if not resultado.success:
            print(f"[AVISO] Intento {intento}: no se pudo abrir {hub_url}: {resultado.error_message}")
            continue

        urls = _extraer_urls_comerciales(resultado, base_url)
        relevantes = [u for u in urls if prefijo_esperado in u]

        if len(relevantes) > len([u for u in mejor_urls if prefijo_esperado in u]):
            mejor_urls = urls

        if len(relevantes) >= minimo_esperado:
            break

        if intento < intentos:
            print(
                f"[AVISO] Hub {hub_url}: solo {len(relevantes)} subcategorías "
                f"relevantes en el intento {intento} (esperaba >= {minimo_esperado}). "
                "Reintentando con más tiempo de espera..."
            )

    return mejor_urls


async def descubrir_categorias(crawler):
    print()
    print("=" * 60)
    print("[FASE 1] DESCUBRIENDO CATEGORÍAS")
    print("=" * 60)

    config = _config_descubrimiento()

    resultado_home = await crawler.arun(url=DOMINIO_BASE, config=config)
    if not resultado_home.success:
        print("[ERROR] No fue posible acceder al homepage.")
        print(f"[ERROR] {resultado_home.error_message}")
        return []

    candidatas = _extraer_urls_comerciales(resultado_home, DOMINIO_BASE)

    # SEGUNDO SALTO: la home de Éxito no expone directamente las
    # subcategorías de supermercado (lácteos, aseo, frutas y verduras...),
    # solo un puñado de colecciones promocionales (tecnología, vinos,
    # moda...) y el hub "/mercado/home". Para llegar a las categorías de
    # canasta familiar reales hay que entrar a ese hub.
    hub_mercado = f"{DOMINIO_BASE}/mercado/home"
    urls_hub = await _extraer_hub_con_reintento(
        crawler, hub_mercado, DOMINIO_BASE, prefijo_esperado="/mercado/"
    )
    for url in urls_hub:
        if url not in candidatas:
            candidatas.append(url)

    aceptadas = []
    descartadas = []

    for url in candidatas:
        path = urlparse(url).path.rstrip("/").lower()
        if es_categoria_valida(url):
            aceptadas.append(url)
        elif path.startswith(PREFIJO_MERCADO):
            segmento = path[len(PREFIJO_MERCADO):].replace("-", " ").replace("/", " ")
            _, motivo = clasificar_categoria(segmento)
            descartadas.append((url, motivo))
        else:
            descartadas.append((url, "fuera de la vertical /mercado/ (no es supermercado)"))

    print(f"[FASE 1] Candidatas comerciales encontradas: {len(candidatas)}")
    print(f"[FASE 1] Categorías aceptadas (canasta familiar): {len(aceptadas)}")
    for indice, url in enumerate(aceptadas, start=1):
        print(f"  [OK]  [{indice}] {url}")
    print(f"[FASE 1] Categorías descartadas: {len(descartadas)}")
    for url, motivo in descartadas[:25]:
        print(f"  [--]  {url}  ({motivo})")
    if len(descartadas) > 25:
        print(f"  ... y {len(descartadas) - 25} más.")

    categorias_limitadas = aceptadas[:MAX_CATEGORIAS]

    ESTADISTICAS_CATEGORIAS["encontradas"] = len(candidatas)
    ESTADISTICAS_CATEGORIAS["aceptadas"] = len(categorias_limitadas)
    ESTADISTICAS_CATEGORIAS["descartadas"] = len(candidatas) - len(categorias_limitadas)

    print()
    print(
        f"[FASE 1] Se procesarán {len(categorias_limitadas)} categorías "
        f"(límite técnico configurado: {MAX_CATEGORIAS})."
    )

    return categorias_limitadas


# ============================================================
# REINTENTOS
# ============================================================

class Reintentar(Exception):
    """Señal para forzar otro intento dentro de con_reintentos()."""


async def con_reintentos(operacion, *, backoff=1.0, max_intentos=MAX_REINTENTOS):
    """
    Ejecuta la corrutina 'operacion' reintentando ante fallos.

    'operacion' debe:
        - devolver el resultado en caso de éxito, o
        - lanzar Reintentar(mensaje) / cualquier excepción para
          forzar otro intento.

    Devuelve (resultado, None) en éxito o (None, ultimo_error) tras
    agotar los intentos.
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


# ============================================================
# VTEX
# ============================================================

def _endpoint_y_params_vtex(categoria_url, pagina):
    """
    Construye el endpoint y los parámetros de búsqueda VTEX para una
    categoría.

    Dos formas de categoría, dos mecánicas VTEX distintas:

      - Colección numérica (/coleccion/<id>): se filtra por
        `fq=productClusterIds:<id>` contra el endpoint de búsqueda base.
        (Ya no se usa tras el filtro de canasta familiar, pero se conserva
        por si alguna vez se vuelve a aceptar una colección explícita.)

      - Categoría por ruta (/mercado/despensa, /mercado/despensa/cafe...):
        VTEX NO acepta esto como `fq=C:{path}` (devuelve HTTP 400 "Can't
        create search criteria"); hay que anexar los segmentos de la ruta
        al propio endpoint y pasar `map=c,c,...` (una "c" por segmento).
        Verificado directamente contra la API pública de Éxito.
    """
    desde = (pagina - 1) * PRODUCTOS_POR_PETICION
    hasta = desde + PRODUCTOS_POR_PETICION - 1

    params = {"_from": desde, "_to": hasta}

    collection_id = extraer_id_coleccion(categoria_url)

    if collection_id:
        params["fq"] = f"productClusterIds:{collection_id}"
        return VTEX_SEARCH_ENDPOINT, params

    segmentos = [s for s in urlparse(categoria_url).path.split("/") if s]
    params["map"] = ",".join(["c"] * len(segmentos)) if segmentos else "c"
    endpoint = "/".join([VTEX_SEARCH_ENDPOINT, *segmentos])

    return endpoint, params


def _extraer_lista_productos(data):
    """Normaliza las distintas formas de respuesta de VTEX a una lista."""
    if isinstance(data, list):
        return data

    if isinstance(data, dict):
        for clave in ("products", "data"):
            valor = data.get(clave)
            if isinstance(valor, list):
                return valor

    return []


async def consultar_vtex(client, categoria_url, pagina):
    endpoint, params = _endpoint_y_params_vtex(categoria_url, pagina)

    async def operacion():
        response = await client.get(endpoint, params=params)
        status = response.status_code

        if status not in (200, 206):
            raise Reintentar(f"HTTP {status}: {response.text[:500]}")

        try:
            data = response.json()
        except json.JSONDecodeError as exc:
            raise Reintentar(f"HTTP {status}: JSON inválido - {exc}")

        return _extraer_lista_productos(data)

    productos, error = await con_reintentos(operacion, backoff=1.5)

    if error is not None:
        print(
            f"[VTEX] Error después de {MAX_REINTENTOS} intentos: {error}"
        )
        return []

    return productos or []


# ============================================================
# LECTURA DE PRODUCTOS VTEX
# ============================================================

def iterar_ofertas(producto):
    """
    Recorre las tuplas (item, seller, commertialOffer) de un producto
    VTEX saltando cualquier estructura mal formada.
    """
    items = producto.get("items", [])
    if not isinstance(items, list):
        return

    for item in items:
        if not isinstance(item, dict):
            continue

        sellers = item.get("sellers", [])
        if not isinstance(sellers, list):
            continue

        for seller in sellers:
            if not isinstance(seller, dict):
                continue

            offer = seller.get("commertialOffer", {})
            if isinstance(offer, dict):
                yield item, seller, offer


def extraer_imagen(producto):
    items = producto.get("items", [])
    if not isinstance(items, list):
        return None

    for item in items:
        if not isinstance(item, dict):
            continue

        images = item.get("images", [])
        if not isinstance(images, list):
            continue

        for image in images:
            if isinstance(image, dict) and image.get("imageUrl"):
                return str(image["imageUrl"]).strip()

    return None


def obtener_nombre_seller(seller):
    nombre = primer_valor(seller, "sellerName", "SellerName", "name")
    if nombre is None:
        return None
    return limpiar_texto(nombre) or None


def obtener_id_seller(seller):
    return a_str(primer_valor(seller, "sellerId", "SellerId", "id"))


def extraer_precios(producto):
    """
    Obtiene exclusivamente los precios comerciales proporcionados por VTEX.

    IMPORTANTE: no extrae medios de pago ni usa Installments.
    """
    menor_price = None
    menor_list_price = None
    seller_ganador = None

    for _item, seller, offer in iterar_ofertas(producto):
        precio = convertir_numero(primer_valor(offer, "Price", "price"))
        if precio is None:
            continue

        if menor_price is None or precio < menor_price:
            menor_price = precio
            menor_list_price = convertir_numero(
                primer_valor(offer, "ListPrice", "listPrice")
            )
            cantidad = convertir_numero(
                primer_valor(offer, "AvailableQuantity", "availableQuantity")
            )
            seller_ganador = {
                "seller_id": obtener_id_seller(seller),
                "seller_name": obtener_nombre_seller(seller),
                "available_quantity": (
                    int(cantidad) if cantidad is not None else None
                ),
            }

    return menor_price, menor_list_price, seller_ganador


def extraer_categoria(producto):
    """
    VTEX devuelve `categories` ordenado de la MÁS específica a la MENOS
    específica, ej.:

        ['/Mercado/Frutas y verduras/Frutas/', '/Mercado/Frutas y verduras/', '/Mercado/']

    Se toma categories[0] (la hoja del árbol, ej. "Frutas"), no
    categories[-1] (la raíz, ej. "Mercado" -- que no dice nada sobre el
    producto y es lo que antes rompía cualquier filtro por nombre de
    categoría).
    """
    category_id = producto.get("categoryId")
    categories = producto.get("categories")

    category = None
    if isinstance(categories, list) and categories:
        category = limpiar_texto(categories[0])
    elif isinstance(categories, str):
        category = limpiar_texto(categories)

    return a_str(category_id), category


def extraer_release_date(producto):
    valor = primer_valor(producto, "releaseDate", "ReleaseDate")
    return limpiar_texto(valor) if valor is not None else None


def extraer_product_reference(producto):
    return primer_valor(producto, "productReference", "reference", "refId")


# ============================================================
# CRAWL4AI - EXTRAER PÁGINA DEL PRODUCTO
# ============================================================

async def obtener_pagina_producto(crawler, product_url):
    config = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        page_timeout=PRODUCT_PAGE_TIMEOUT,
        delay_before_return_html=3,
        wait_for="css:body",
        magic=True,
        simulate_user=True,
        override_navigator=True,
    )

    async def operacion():
        resultado = await crawler.arun(url=product_url, config=config)
        if not resultado.success:
            raise Reintentar(resultado.error_message)
        return resultado

    resultado, error = await con_reintentos(operacion, backoff=1.0)

    if error is not None:
        print(f"[PRODUCTO] No se pudo cargar: {product_url}")
        print(f"[PRODUCTO] Error: {error}")
        return None

    return resultado


# ============================================================
# MÉTODOS DE PAGO
# ============================================================

def normalizar_nombre_pago(nombre):
    """
    Convierte una etiqueta de la página al nombre canónico del método.
    Si la etiqueta no pertenece a la lista blanca, devuelve None.

    Esto es lo que evita que entren: Carrito, Menu, 1 Opinión, etc.
    """
    if not nombre:
        return None

    # Eliminar Markdown / caracteres de formato.
    nombre = re.sub(r"[*_`]", "", str(nombre))
    nombre = limpiar_texto(nombre).strip(" :|-")

    if not nombre:
        return None

    clave = nombre.casefold()

    if clave in METODOS_PAGO_INVALIDOS:
        return None

    return METODOS_PAGO_VALIDOS.get(clave)


def extraer_bloque_precios_pago(markdown):
    """
    Obtiene la zona inicial de la página donde Éxito presenta los
    precios/promociones. Se corta antes de "Ofertas adicionales".
    """
    if not markdown:
        return ""

    texto = markdown.replace("\r\n", "\n").replace("\r", "\n")

    match_fin = re.search(r"Ofertas\s+adicionales", texto, re.IGNORECASE)
    if match_fin:
        texto = texto[: match_fin.start()]

    return texto


def extraer_precios_visibles(texto):
    """
    Extrae precios visibles y conserva su posición dentro del texto.

    Ejemplo: "$ 2.099.900" -> {"price": 2099900, "position": ...}
    """
    patron = re.compile(
        r"""
        (?:\*\*)?
        \$\s*
        ([\d\.,]+)
        (?:\*\*)?
        """,
        re.VERBOSE,
    )

    resultados = []
    for match in patron.finditer(texto or ""):
        numero = convertir_numero(match.group(1))
        if numero is not None:
            resultados.append({"price": numero, "position": match.start()})

    return resultados


def extraer_etiquetas_pago(markdown):
    """
    Extrae ÚNICAMENTE etiquetas que correspondan a métodos de pago de
    la lista blanca, en dos formas:

        1. Imágenes/enlaces Markdown:  [mastercard](...)
        2. Texto plano:                Otros

    Todo lo demás es ignorado ([Carrito], [Menu], [1 Opinión], ...).
    """
    if not markdown:
        return []

    resultados = []

    # 1. ENLACES / IMÁGENES MARKDOWN
    patron_links = re.compile(r"\[([^\]]+)\]\([^\)]+\)", re.IGNORECASE)
    for match in patron_links.finditer(markdown):
        metodo = normalizar_nombre_pago(limpiar_texto(match.group(1)))
        if metodo is None:
            continue
        resultados.append(
            {
                "method": metodo,
                "position": match.start(),
                "end_position": match.end(),
                "source": "markdown_link",
            }
        )

    # 2. "OTROS" COMO TEXTO PLANO
    #
    # "Otros" puede aparecer como texto normal y no como [Otros](...),
    # por eso se busca explícitamente como una línea independiente.
    for match in re.finditer(r"(?im)^\s*Otros\s*$", markdown):
        resultados.append(
            {
                "method": "Otros",
                "position": match.start(),
                "end_position": match.end(),
                "source": "plain_text",
            }
        )

    resultados.sort(key=lambda item: item["position"])

    # DEDUPLICAR POSICIONES
    unicos = []
    posiciones_vistas = set()
    for item in resultados:
        clave = (item["method"].casefold(), item["position"])
        if clave in posiciones_vistas:
            continue
        posiciones_vistas.add(clave)
        unicos.append(item)

    return unicos


def extraer_medios_pago_desde_pagina(markdown):
    """
    Extrae métodos de pago visibles en la página real del producto.

    La asociación se realiza por PROXIMIDAD entre método y precio, no
    simplemente buscando el precio posterior. Esto maneja:

        [mastercard]        $ 2.449.900
        $ 2.449.900         [mastercard]
        $ 2.699.900         Otros

    No se utilizan Installments ni PaymentSystems.
    """
    if not markdown:
        return []

    bloque = extraer_bloque_precios_pago(markdown)
    if not bloque:
        return []

    precios = extraer_precios_visibles(bloque)
    etiquetas = extraer_etiquetas_pago(bloque)

    if not precios or not etiquetas:
        return []

    # Distancia máxima entre método y precio. Evita asociaciones con
    # precios completamente ajenos y evita recorrer toda la página.
    DISTANCIA_MAXIMA = 350

    # ASOCIAR CADA MÉTODO CON EL PRECIO MÁS CERCANO
    candidatos = []
    for etiqueta in etiquetas:
        posicion_metodo = etiqueta["position"]

        mejores = [
            {
                "price": precio,
                "distance": abs(posicion_metodo - precio["position"]),
                # En Éxito es frecuente el precio ANTES del método, por
                # eso ante empate se prefiere el precio anterior.
                "price_after_method": precio["position"] > posicion_metodo,
            }
            for precio in precios
            if abs(posicion_metodo - precio["position"]) <= DISTANCIA_MAXIMA
        ]

        if not mejores:
            continue

        candidato = min(
            mejores,
            key=lambda item: (
                item["distance"],
                1 if item["price_after_method"] else 0,
            ),
        )

        candidatos.append(
            {
                "method": etiqueta["method"],
                "price": candidato["price"]["price"],
                "method_position": posicion_metodo,
                "price_position": candidato["price"]["position"],
                "distance": candidato["distance"],
            }
        )

    if not candidatos:
        return []

    # RESOLVER COLISIONES: dos métodos no deben quedarse con el mismo
    # precio cuando existe una alternativa mejor.
    candidatos.sort(
        key=lambda item: (item["distance"], item["method_position"])
    )

    resultados = []
    precios_utilizados = set()
    metodos_vistos = set()

    for candidato in candidatos:
        precio_key = candidato["price_position"]
        metodo_key = candidato["method"].casefold()

        # Un precio solo se asigna una vez, y cada método una sola vez.
        if precio_key in precios_utilizados or metodo_key in metodos_vistos:
            continue

        precios_utilizados.add(precio_key)
        metodos_vistos.add(metodo_key)

        resultados.append(
            {
                "method": candidato["method"],
                "total_price": candidato["price"],
            }
        )

    # ORDEN ORIGINAL DE LA PÁGINA
    posicion_por_metodo = {
        candidato["method"].casefold(): candidato["method_position"]
        for candidato in candidatos
    }
    resultados.sort(
        key=lambda item: posicion_por_metodo.get(
            item["method"].casefold(), 999999999
        )
    )

    return resultados


def extraer_payment_methods(resultado):
    """
    Utiliza exclusivamente el contenido visible generado por Crawl4AI.

    No usa Installments, PaymentSystems, commertialOffer ni APIs internas
    de VTEX para determinar métodos de pago.
    """
    if resultado is None:
        return []

    markdown = getattr(resultado, "markdown", None)
    if not isinstance(markdown, str):
        return []

    return extraer_medios_pago_desde_pagina(markdown)


# ============================================================
# CONSTRUIR PRODUCTO
# ============================================================

def _resolver_link(producto):
    """Obtiene el link del producto a partir de sus posibles campos."""
    link = primer_valor(producto, "link", "productUrl")

    if not link:
        link_text = producto.get("linkText")
        if link_text:
            link = f"/{str(link_text).strip()}/p"

    return link


def construir_producto(producto, categoria_url, pagina, extracted_at):
    if not isinstance(producto, dict):
        return None

    # ID
    product_id = primer_valor(producto, "productId", "id")
    if product_id is None:
        return None
    product_id = str(product_id).strip()
    if not product_id:
        return None

    # NOMBRE
    nombre = limpiar_texto(producto.get("productName"))
    if not nombre:
        return None

    # URL
    link = _resolver_link(producto)
    if not link:
        return None

    product_url = normalizar_product_url(link)
    if not product_url or not es_producto_url(product_url):
        return None

    # MARCA
    brand = limpiar_texto(producto.get("brand")) or None
    brand_id = a_str(producto.get("brandId"))

    # CATEGORÍA
    category_id, category = extraer_categoria(producto)

    # RESTO
    release_date = extraer_release_date(producto)
    product_reference = a_str(extraer_product_reference(producto))
    price, list_price, seller_info = extraer_precios(producto)
    image_url = extraer_imagen(producto)

    seller_info = seller_info or {}

    return {
        "source": SOURCE,
        "product_id": product_id,
        "product_name": nombre,
        "brand": brand,
        "brand_id": brand_id,
        "product_reference": product_reference,
        "product_reference_code": product_reference,
        "category_id": category_id,
        "category": category,
        "price": price,
        "list_price": list_price,
        "currency": "COP",
        "image_url": image_url,
        "product_url": product_url,
        "source_category_url": categoria_url,
        "page": pagina,
        "release_date": release_date,
        "seller_id": seller_info.get("seller_id"),
        "seller_name": seller_info.get("seller_name"),
        "seller_available_quantity": seller_info.get("available_quantity"),
        # Se completa posteriormente desde el PDP real.
        "payment_methods": [],
        "extracted_at": extracted_at,
    }


# ============================================================
# ENRIQUECER CON PÁGINA REAL
# ============================================================

async def enriquecer_producto_con_pagina(crawler, producto):
    product_url = producto.get("product_url")
    if not product_url:
        return producto

    print(f"[PDP] {producto.get('product_name', '')}")

    resultado = await obtener_pagina_producto(crawler, product_url)

    if resultado is None:
        print("[PDP] Sin datos de métodos de pago.")
        return producto

    payment_methods = extraer_payment_methods(resultado)
    producto["payment_methods"] = payment_methods

    if payment_methods:
        print("[PDP] Métodos encontrados:")
        for metodo in payment_methods:
            print(f"      {metodo['method']}: ${metodo['total_price']:,.0f}")
    else:
        print(
            "[PDP] No se encontraron métodos promocionales verificables."
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
        if not product_id:
            continue

        existente = unicos.get(product_id)

        if existente is None:
            unicos[product_id] = producto
            continue

        precio_existente = convertir_numero(existente.get("price"))
        precio_nuevo = convertir_numero(producto.get("price"))

        nuevo_es_mejor = precio_nuevo is not None and (
            precio_existente is None or precio_nuevo < precio_existente
        )

        if nuevo_es_mejor:
            # El nuevo gana, pero hereda los campos que le falten.
            completar_campos_vacios(producto, existente)
            unicos[product_id] = producto
        else:
            # Se conserva el existente, completando sus huecos.
            completar_campos_vacios(existente, producto)

    return list(unicos.values())


# ============================================================
# CALIDAD
# ============================================================

CAMPOS_CALIDAD = [
    "brand",
    "brand_id",
    "category_id",
    "category",
    "release_date",
    "image_url",
    "price",
    "list_price",
    "seller_id",
    "seller_name",
    "product_url",
    "payment_methods",
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
    client,
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

    # PAGINACIÓN DINÁMICA POR DENSIDAD: ver Carulla para el detalle. Éxito
    # descubre "mercado/despensa" (nodo padre, alto volumen) y también
    # alguna subcategoría suya (ej. "cafe-chocolate..."), pero el resto de
    # despensa (arroz, aceites, granos...) solo se cubre a través del nodo
    # padre -- sin este multiplicador quedaría igual de truncado que
    # Carulla.
    segmentos_categoria = [s for s in urlparse(categoria_url).path.split("/") if s]
    texto_categoria = " ".join(segmentos_categoria).replace("-", " ")
    max_paginas = MAX_PAGINAS_POR_CATEGORIA * factor_paginas(texto_categoria)
    if max_paginas != MAX_PAGINAS_POR_CATEGORIA:
        print(
            f"[PAGINACIÓN] Categoría de alta densidad detectada: "
            f"{max_paginas} páginas (en vez de {MAX_PAGINAS_POR_CATEGORIA})."
        )

    for pagina in range(1, max_paginas + 1):
        print()
        print("-" * 60)
        print("[PÁGINA]")
        print(f"Categoría: {categoria_url}")
        print(f"Página:    {pagina}")
        print(
            "URL:       "
            f"{construir_url_pagina_categoria(categoria_url, pagina)}"
        )
        print("-" * 60)

        inicio = time.perf_counter()
        data = await consultar_vtex(client, categoria_url, pagina)
        duracion = time.perf_counter() - inicio

        print(
            f"[VTEX] Productos recibidos: {len(data)} | {duracion:.2f}s"
        )

        if not data:
            print(f"[PAGINACIÓN] Página {pagina} sin productos.")
            break

        extracted_at = obtener_timestamp_actual()

        productos_validos = [
            normalizado
            for producto in data
            if (
                normalizado := construir_producto(
                    producto, categoria_url, pagina, extracted_at
                )
            )
            is not None
        ]

        print(f"[RESULTADO] Productos válidos: {len(productos_validos)}")

        # FILTRO DEFENSIVO DE CANASTA FAMILIAR
        #
        # La URL de categoría ya fue aceptada por es_categoria_valida(), pero
        # el campo `categories` de VTEX es la fuente más específica (un
        # mismo listado puede mezclar productos de otra categoría real).
        # Solo se descarta cuando SÍ hay texto de categoría y el
        # clasificador lo rechaza explícitamente; si no hay texto, se
        # conserva el producto (ya pasó el filtro por URL).
        antes = len(productos_validos)
        productos_validos = [
            producto
            for producto in productos_validos
            if not producto.get("category")
            or clasificar_categoria(producto["category"])[0]
        ]
        descartados_por_categoria = antes - len(productos_validos)
        if descartados_por_categoria:
            print(
                f"[FILTRO CANASTA] Descartados por categoría fuera de "
                f"alcance: {descartados_por_categoria}"
            )

        # CONSULTAR PDP REAL
        for producto in productos_validos:
            await enriquecer_producto_con_pagina(crawler, producto)

        productos_categoria.extend(productos_validos)

        if len(data) < PRODUCTOS_POR_PETICION:
            print("[PAGINACIÓN] Respuesta menor al tamaño de página.")
            break

        await asyncio.sleep(DELAY_ENTRE_PETICIONES)

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
    payload = {
        "source": SOURCE,
        "start_url": DOMINIO_BASE,
        "extraction_started_at": extraction_started_at,
        "extraction_finished_at": extraction_finished_at,
        "timezone": "America/Bogota",
        "categories_processed": categorias_procesadas,
        "max_categories": MAX_CATEGORIAS,
        "max_pages_per_category": MAX_PAGINAS_POR_CATEGORIA,
        "products_per_request": PRODUCTOS_POR_PETICION,
        "products_found": len(productos),
        "products_unique": len(productos),
        "products": productos,
    }

    ruta_escrita = guardar_raw_snapshot(RUTA_RAW, SOURCE, payload)

    return payload, ruta_escrita


# ============================================================
# MAIN
# ============================================================

async def main():
    extraction_started_at = obtener_timestamp_actual()

    print()
    print("=" * 60)
    print("PREZIO - SCRAPER EXITO")
    print("=" * 60)
    print(f"Inicio extracción: {extraction_started_at}")
    print(f"URL inicial: {DOMINIO_BASE}")
    print(f"Máximo categorías: {MAX_CATEGORIAS}")
    print(f"Máximo páginas/categoría: {MAX_PAGINAS_POR_CATEGORIA}")
    print(f"Productos por petición: {PRODUCTOS_POR_PETICION}")
    print(f"Endpoint VTEX: {VTEX_SEARCH_ENDPOINT}")
    print(f"Concurrencia HTTP: {CONCURRENCIA}")
    print("Métodos de pago: PDP REAL DE ÉXITO")
    print("Filtro de métodos: LISTA BLANCA")
    print("Zona horaria: America/Bogota")
    print()

    browser_config = BrowserConfig(
        headless=True,
        verbose=False,
        user_agent=HEADERS["User-Agent"],
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

        limits = httpx.Limits(
            max_connections=CONCURRENCIA,
            max_keepalive_connections=CONCURRENCIA,
        )
        timeout = httpx.Timeout(HTTP_TIMEOUT)

        async with httpx.AsyncClient(
            headers=HEADERS,
            timeout=timeout,
            limits=limits,
            follow_redirects=True,
        ) as client:
            for indice, categoria_url in enumerate(categorias, start=1):
                productos_categoria = await procesar_categoria(
                    client,
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

        _, ruta_raw_escrita = guardar_raw(
            productos_totales,
            len(categorias),
            extraction_started_at,
            extraction_finished_at,
        )

        print()
        print("=" * 60)
        print("[REPORTE CANASTA FAMILIAR]")
        print("=" * 60)
        print("Éxito:")
        print(f"  Categorías encontradas:  {ESTADISTICAS_CATEGORIAS['encontradas']}")
        print(f"  Categorías aceptadas:    {ESTADISTICAS_CATEGORIAS['aceptadas']}")
        print(f"  Categorías descartadas:  {ESTADISTICAS_CATEGORIAS['descartadas']}")
        print(f"  Productos obtenidos:     {len(productos_totales)}")

        print()
        print(f"Archivo: {ruta_raw_escrita}")
        print()
        print("=" * 60)
        print("[FIN]")
        print("=" * 60)


# ============================================================
# EJECUCIÓN
# ============================================================

if __name__ == "__main__":
    asyncio.run(main())