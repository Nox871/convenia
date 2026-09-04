import asyncio
import json
import re
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


# ============================================================
# CONFIGURACIÓN
# ============================================================

SOURCE = "JUMBO"

DOMINIO_BASE = "https://www.jumbocolombia.com"

MAX_CATEGORIAS = 20
MAX_PAGINAS_POR_CATEGORIA = 2

# VTEX permite consultar hasta 50 productos por petición.
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

# scraper/connectors/jumbo/scraper.py
#
# parents:
#   jumbo -> connectors
#   connectors -> scraper
#   scraper -> prezio
#
# parents[3] = raíz del proyecto

BASE_PROYECTO = Path(__file__).resolve().parents[3]

RUTA_RAW = (
    BASE_PROYECTO
    / "data"
    / "raw"
    / "jumbo"
    / "productos"
)

RUTA_RAW_JSON = RUTA_RAW / "jumbo_raw.json"

RUTA_DEBUG = (
    BASE_PROYECTO
    / "data"
    / "raw"
    / "jumbo"
    / "debug"
)


# ============================================================
# ENDPOINT VTEX
# ============================================================

VTEX_SEARCH_ENDPOINT = (
    f"{DOMINIO_BASE}"
    "/api/catalog_system/pub/products/search"
)


# ============================================================
# HEADERS
# ============================================================

HEADERS = {

    "Accept": (
        "application/json, "
        "text/plain, "
        "*/*"
    ),

    "Accept-Language": (
        "es-CO,es;q=0.9,en;q=0.8"
    ),

    "User-Agent": (
        "Mozilla/5.0 "
        "(Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 "
        "(KHTML, like Gecko) "
        "Chrome/151.0.0.0 "
        "Safari/537.36"
    ),

    "Referer": (
        f"{DOMINIO_BASE}/"
    ),

    "Connection": "keep-alive",
}


# ============================================================
# FILTROS DE URL
# ============================================================

PATRONES_OMITIR = re.compile(
    r"""
    (
        cuenta |
        carrito |
        checkout |
        login |
        authentication |
        autorizacion |
        ayuda |
        legal |
        terminos |
        condiciones |
        politica |
        privacidad |
        institucional |
        contacto |
        trabaja |
        empleo |
        nosotros |
        blog |
        puntos |
        referidos |
        favoritos |
        wishlist |
        pedidos |
        ordenes |
        mi-cuenta |
        servicio-al-cliente |
        servicio_cliente |
        vendedores |
        marketplace |
        garantia |
        habeas |
        sitemap |
        promociones |
        promociones- |
        newsletter |
        registro
    )
    """,
    re.IGNORECASE | re.VERBOSE,
)


# ============================================================
# MÉTODOS DE PAGO
# ============================================================
#
# LISTA BLANCA.
#
# Solo se aceptan nombres que realmente correspondan
# a medios de pago conocidos.
#
# Esto evita capturar:
#
#   Comprar
#   Agregar
#   Carrito
#   Opiniones
#   Ver más
#   etc.
#
# Si Jumbo incorpora un método adicional, se puede agregar
# posteriormente aquí.
#

METODOS_PAGO_VALIDOS = {

    # Tarjetas
    "visa": "visa",

    "mastercard": "mastercard",
    "master card": "mastercard",

    "american express": "american express",
    "amex": "american express",

    "diners": "diners",
    "diners club": "diners",

    # Cencosud / Jumbo
    "cencosud": "cencosud",
    "tarjeta cencosud": "cencosud",

    # Bancos / medios digitales
    "bancolombia": "bancolombia",
    "pse": "pse",
    "nequi": "nequi",
    "daviplata": "daviplata",

    # Otros
    "maestro": "maestro",
    "codensa": "codensa",
    "tuya": "tuya",

    # Texto genérico que puede aparecer en el bloque
    "otros": "Otros",
}


# ============================================================
# TEXTOS QUE JAMÁS DEBEN SER MÉTODOS DE PAGO
# ============================================================

METODOS_PAGO_INVALIDOS = {

    "carrito",
    "cart",
    "menu",
    "menú",

    "comprar",
    "comprar ahora",

    "agregar",
    "agregar al carrito",

    "añadir",
    "añadir al carrito",

    "opinión",
    "opinion",
    "opiniones",

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

    "ver más",
    "ver mas",

    "detalles",

    "favoritos",
    "añadir a favoritos",

    "cantidad",
    "unidades",

    "disponibilidad",
}


# ============================================================
# FECHA / HORA
# ============================================================

def obtener_timestamp_actual():

    return datetime.now(
        TIMEZONE
    ).isoformat(
        timespec="seconds"
    )


# ============================================================
# UTILIDADES
# ============================================================

def limpiar_texto(valor):

    if valor is None:
        return ""

    texto = str(valor)

    texto = texto.replace(
        "\xa0",
        " "
    )

    texto = re.sub(
        r"\s+",
        " ",
        texto
    )

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

    if valor is None:
        return None

    if isinstance(valor, bool):
        return None

    if isinstance(
        valor,
        (int, float)
    ):

        return float(valor)

    texto = limpiar_texto(
        valor
    )

    if not texto:
        return None

    texto = re.sub(
        r"[^\d,.\-]",
        "",
        texto
    )

    if not texto:
        return None

    # --------------------------------------------------------
    # 12.990
    # 3.859.500
    # --------------------------------------------------------

    if (
        "." in texto
        and "," not in texto
    ):

        partes = texto.split(".")

        if (
            len(partes) > 1
            and all(
                len(parte) == 3
                for parte in partes[1:]
            )
        ):

            texto = "".join(
                partes
            )

    # --------------------------------------------------------
    # 12,990
    # --------------------------------------------------------

    elif (
        "," in texto
        and "." not in texto
    ):

        partes = texto.split(",")

        if (
            len(partes) > 1
            and all(
                len(parte) == 3
                for parte in partes[1:]
            )
        ):

            texto = "".join(
                partes
            )

        else:

            texto = texto.replace(
                ",",
                "."
            )

    # --------------------------------------------------------
    # 3.859,50
    # --------------------------------------------------------

    elif (
        "." in texto
        and "," in texto
    ):

        if (
            texto.rfind(",")
            >
            texto.rfind(".")
        ):

            texto = (
                texto
                .replace(".", "")
                .replace(",", ".")
            )

        else:

            texto = texto.replace(
                ",",
                ""
            )

    try:

        return float(
            texto
        )

    except ValueError:

        return None


# ============================================================
# NORMALIZACIÓN DE URL
# ============================================================

def normalizar_url(url):

    if not url:
        return ""

    url = str(
        url
    ).strip()

    parsed = urlparse(
        url
    )

    if not parsed.scheme:

        url = urljoin(
            DOMINIO_BASE,
            url
        )

        parsed = urlparse(
            url
        )

    return urlunparse(
        (
            parsed.scheme.lower(),
            parsed.netloc.lower(),
            parsed.path,
            "",
            "",
            "",
        )
    )


def normalizar_product_url(url):

    if not url:
        return None

    url = str(
        url
    ).strip()

    if not urlparse(
        url
    ).scheme:

        url = urljoin(
            DOMINIO_BASE,
            url
        )

    parsed = urlparse(
        url
    )

    hostname = (
        parsed.netloc
        .lower()
    )

    dominios_validos = {
        "www.jumbocolombia.com",
        "jumbocolombia.com",
    }

    if hostname not in dominios_validos:

        return None

    hostname = (
        "www.jumbocolombia.com"
    )

    return urlunparse(
        (
            parsed.scheme.lower(),
            hostname,
            parsed.path,
            "",
            "",
            "",
        )
    )


def es_producto_url(url):

    if not url:
        return False

    parsed = urlparse(
        url
    )

    path = (
        parsed.path
        .rstrip("/")
        .lower()
    )

    return path.endswith(
        "/p"
    )


def es_url_comercial(url):

    try:

        parsed = urlparse(
            url
        )

        if (
            parsed.netloc.lower()
            not in {
                "www.jumbocolombia.com",
                "jumbocolombia.com",
            }
        ):

            return False

        path = (
            parsed.path
            .rstrip("/")
            .lower()
        )

        if not path:
            return False

        if path.endswith(
            "/p"
        ):

            return False

        if re.search(
            r"\.(pdf|jpg|jpeg|png|gif|webp|svg|xml|json|css|js)$",
            path,
            re.IGNORECASE,
        ):

            return False

        if PATRONES_OMITIR.search(
            path
        ):

            return False

        if path.startswith(
            "/_next/"
        ):

            return False

        if path.startswith(
            "/api/"
        ):

            return False

        return True

    except Exception:

        return False


# ============================================================
# CATEGORÍAS
# ============================================================

def es_categoria_valida(url):

    if not es_url_comercial(
        url
    ):

        return False

    parsed = urlparse(
        url
    )

    path = (
        parsed.path
        .rstrip("/")
        .lower()
    )

    if not path:
        return False

    # Las páginas de categoría de Jumbo Colombia
    # normalmente utilizan rutas comerciales.
    #
    # Se descartan páginas demasiado profundas,
    # productos y páginas institucionales.

    segmentos = [
        segmento
        for segmento in path.split("/")
        if segmento
    ]

    if not segmentos:
        return False

    # Una sola sección normalmente corresponde
    # a una categoría/landing válida.
    if len(segmentos) == 1:

        return True

    # Categorías comerciales profundas.
    prefijos = (
        "/despensa/",
        "/bebidas/",
        "/aseo/",
        "/electrohogar/",
        "/electro-hogar/",
        "/tecnologia/",
        "/hogar/",
        "/mascotas/",
        "/jugueteria/",
        "/juguetes/",
        "/moda/",
        "/deportes/",
        "/belleza/",
        "/salud/",
        "/canasta/",
        "/supermercado/",
    )

    if path.startswith(
        prefijos
    ):

        return True

    # Cualquier URL que no parezca una página
    # institucional puede ser utilizada como
    # categoría potencial.
    #
    # Esto es deliberadamente más flexible que Éxito
    # porque Jumbo puede cambiar sus nombres de categoría.

    if len(segmentos) <= 3:

        return True

    return False


# ============================================================
# EXTRAER ID DE COLECCIÓN
# ============================================================

def extraer_id_coleccion(url):

    parsed = urlparse(
        url
    )

    match = re.search(
        r"/coleccion/(\d+)",
        parsed.path,
        re.IGNORECASE,
    )

    if not match:

        return None

    return match.group(1)


# ============================================================
# CONSTRUIR URL DE PÁGINA
# ============================================================

def construir_url_pagina_categoria(
    categoria_url,
    pagina,
):

    parsed = urlparse(
        categoria_url
    )

    query = parse_qs(
        parsed.query,
        keep_blank_values=True,
    )

    query["page"] = [
        str(pagina)
    ]

    nueva_query = urlencode(
        query,
        doseq=True,
    )

    return urlunparse(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            parsed.params,
            nueva_query,
            parsed.fragment,
        )
    )


# ============================================================
# FASE 1 - DESCUBRIR CATEGORÍAS
# ============================================================

async def descubrir_categorias(
    crawler
):

    print()

    print("=" * 60)

    print(
        "[FASE 1] "
        "DESCUBRIENDO CATEGORÍAS JUMBO"
    )

    print("=" * 60)

    config = CrawlerRunConfig(

        cache_mode=CacheMode.BYPASS,

        wait_for="css:body",

        delay_before_return_html=3,

        page_timeout=120000,

        magic=True,

        simulate_user=True,

        override_navigator=True,
    )

    resultado = await crawler.arun(
        url=DOMINIO_BASE,
        config=config,
    )

    if not resultado.success:

        print(
            "[ERROR] No fue posible acceder "
            "al homepage de Jumbo."
        )

        print(
            f"[ERROR] "
            f"{resultado.error_message}"
        )

        return []

    enlaces = (
        resultado.links.get(
            "internal",
            []
        )
    )

    categorias = []

    vistas = set()

    for enlace in enlaces:

        href = enlace.get(
            "href",
            ""
        )

        if not href:
            continue

        url = urljoin(
            DOMINIO_BASE,
            href
        )

        url = normalizar_url(
            url
        )

        if not es_categoria_valida(
            url
        ):

            continue

        if url in vistas:

            continue

        vistas.add(
            url
        )

        categorias.append(
            url
        )

    print(
        "[FASE 1] Categorías potenciales "
        f"encontradas: {len(categorias)}"
    )

    for indice, url in enumerate(
        categorias,
        start=1
    ):

        print(
            f"  [{indice}] {url}"
        )

    categorias_limitadas = (
        categorias[
            :MAX_CATEGORIAS
        ]
    )

    print()

    print(
        "[FASE 1] Se procesarán "
        f"{len(categorias_limitadas)} "
        "categorías "
        "(límite configurado: "
        f"{MAX_CATEGORIAS})."
    )

    return categorias_limitadas


# ============================================================
# VTEX
# ============================================================

async def consultar_vtex(
    client,
    categoria_url,
    pagina,
):

    desde = (
        (pagina - 1)
        * PRODUCTOS_POR_PETICION
    )

    hasta = (
        desde
        + PRODUCTOS_POR_PETICION
        - 1
    )

    collection_id = (
        extraer_id_coleccion(
            categoria_url
        )
    )

    params = {

        "_from": desde,

        "_to": hasta,
    }

    if collection_id:

        params["fq"] = (
            "productClusterIds:"
            f"{collection_id}"
        )

    else:

        parsed = urlparse(
            categoria_url
        )

        path = (
            parsed.path
            .strip("/")
        )

        # VTEX category filter.
        #
        # En tiendas VTEX:
        #
        # map=c
        # fq=C:<ruta>

        params["map"] = "c"

        params["fq"] = (
            f"C:{path}"
        )

    ultimo_error = None

    for intento in range(
        1,
        MAX_REINTENTOS + 1
    ):

        try:

            response = await client.get(
                VTEX_SEARCH_ENDPOINT,
                params=params,
            )

            status = (
                response.status_code
            )

            if status in (
                200,
                206
            ):

                try:

                    data = (
                        response.json()
                    )

                except json.JSONDecodeError as exc:

                    ultimo_error = (
                        f"HTTP {status}: "
                        f"JSON inválido - {exc}"
                    )

                    if (
                        intento
                        <
                        MAX_REINTENTOS
                    ):

                        await asyncio.sleep(
                            intento * 1.5
                        )

                    continue

                if isinstance(
                    data,
                    list
                ):

                    return data

                if isinstance(
                    data,
                    dict
                ):

                    productos = (
                        data.get(
                            "products"
                        )
                    )

                    if isinstance(
                        productos,
                        list
                    ):

                        return productos

                    data_inner = (
                        data.get(
                            "data"
                        )
                    )

                    if isinstance(
                        data_inner,
                        list
                    ):

                        return data_inner

                return []

            ultimo_error = (
                f"HTTP {status}: "
                f"{response.text[:500]}"
            )

        except (
            httpx.TimeoutException,
            httpx.NetworkError,
            httpx.HTTPError,
            json.JSONDecodeError,
        ) as exc:

            ultimo_error = str(
                exc
            )

        except Exception as exc:

            ultimo_error = str(
                exc
            )

        if (
            intento
            <
            MAX_REINTENTOS
        ):

            await asyncio.sleep(
                intento * 1.5
            )

    print(
        "[VTEX] Error después de "
        f"{MAX_REINTENTOS} intentos: "
        f"{ultimo_error}"
    )

    return []


# ============================================================
# IMAGEN
# ============================================================

def extraer_imagen(
    producto
):

    items = producto.get(
        "items",
        []
    )

    if not isinstance(
        items,
        list
    ):

        return None

    for item in items:

        if not isinstance(
            item,
            dict
        ):

            continue

        images = item.get(
            "images",
            []
        )

        if not isinstance(
            images,
            list
        ):

            continue

        for image in images:

            if not isinstance(
                image,
                dict
            ):

                continue

            image_url = (
                image.get(
                    "imageUrl"
                )
            )

            if image_url:

                return str(
                    image_url
                ).strip()

    return None


# ============================================================
# SELLERS
# ============================================================

def obtener_nombre_seller(
    seller
):

    if not isinstance(
        seller,
        dict
    ):

        return None

    nombre = (

        seller.get(
            "sellerName"
        )

        or seller.get(
            "SellerName"
        )

        or seller.get(
            "name"
        )
    )

    if nombre is None:

        return None

    nombre = limpiar_texto(
        nombre
    )

    return (
        nombre
        or None
    )


def obtener_id_seller(
    seller
):

    if not isinstance(
        seller,
        dict
    ):

        return None

    seller_id = (

        seller.get(
            "sellerId"
        )

        or seller.get(
            "SellerId"
        )

        or seller.get(
            "id"
        )
    )

    if seller_id is None:

        return None

    return str(
        seller_id
    )


# ============================================================
# PRECIOS VTEX
# ============================================================

def extraer_precios(
    producto
):

    """
    Obtiene exclusivamente precios comerciales
    provenientes de VTEX.

    NO utiliza Installments para determinar
    el precio comercial.
    """

    menor_price = None

    menor_list_price = None

    seller_ganador = None

    items = producto.get(
        "items",
        []
    )

    if not isinstance(
        items,
        list
    ):

        return (
            None,
            None,
            None,
        )

    for item in items:

        if not isinstance(
            item,
            dict
        ):

            continue

        sellers = item.get(
            "sellers",
            []
        )

        if not isinstance(
            sellers,
            list
        ):

            continue

        for seller in sellers:

            if not isinstance(
                seller,
                dict
            ):

                continue

            offer = seller.get(
                "commertialOffer",
                {}
            )

            if not isinstance(
                offer,
                dict
            ):

                continue

            precio_raw = (

                offer.get(
                    "Price"
                )

                if offer.get(
                    "Price"
                ) is not None

                else offer.get(
                    "price"
                )
            )

            precio = convertir_numero(
                precio_raw
            )

            if precio is None:

                continue

            list_price_raw = (

                offer.get(
                    "ListPrice"
                )

                if offer.get(
                    "ListPrice"
                ) is not None

                else offer.get(
                    "listPrice"
                )
            )

            list_price = convertir_numero(
                list_price_raw
            )

            available_quantity = (

                offer.get(
                    "AvailableQuantity"
                )

                if offer.get(
                    "AvailableQuantity"
                ) is not None

                else offer.get(
                    "availableQuantity"
                )
            )

            available_quantity = (
                convertir_numero(
                    available_quantity
                )
            )

            if (
                menor_price is None
                or precio < menor_price
            ):

                menor_price = precio

                menor_list_price = (
                    list_price
                )

                seller_ganador = {

                    "seller_id":
                        obtener_id_seller(
                            seller
                        ),

                    "seller_name":
                        obtener_nombre_seller(
                            seller
                        ),

                    "available_quantity":
                        (
                            int(
                                available_quantity
                            )
                            if (
                                available_quantity
                                is not None
                            )
                            else None
                        ),
                }

    return (
        menor_price,
        menor_list_price,
        seller_ganador,
    )


# ============================================================
# CRAWL4AI - PRODUCT PAGE
# ============================================================

async def obtener_pagina_producto(
    crawler,
    product_url,
):

    config = CrawlerRunConfig(

        cache_mode=CacheMode.BYPASS,

        page_timeout=PRODUCT_PAGE_TIMEOUT,

        delay_before_return_html=3,

        wait_for="css:body",

        magic=True,

        simulate_user=True,

        override_navigator=True,
    )

    ultimo_error = None

    for intento in range(
        1,
        MAX_REINTENTOS + 1
    ):

        try:

            resultado = (
                await crawler.arun(
                    url=product_url,
                    config=config,
                )
            )

            if resultado.success:

                return resultado

            ultimo_error = (
                resultado.error_message
            )

        except Exception as exc:

            ultimo_error = str(
                exc
            )

        if (
            intento
            <
            MAX_REINTENTOS
        ):

            await asyncio.sleep(
                intento
            )

    print(
        "[PRODUCTO] No se pudo cargar: "
        f"{product_url}"
    )

    print(
        "[PRODUCTO] Error: "
        f"{ultimo_error}"
    )

    return None


# ============================================================
# MÉTODOS DE PAGO
# ============================================================

def normalizar_nombre_pago(
    nombre
):

    if not nombre:

        return None

    nombre = str(
        nombre
    )

    nombre = re.sub(
        r"[\*\_\`]",
        "",
        nombre
    )

    nombre = limpiar_texto(
        nombre
    )

    nombre = nombre.strip(
        " :|-"
    )

    if not nombre:

        return None

    clave = nombre.casefold()

    if (
        clave
        in METODOS_PAGO_INVALIDOS
    ):

        return None

    metodo = (
        METODOS_PAGO_VALIDOS.get(
            clave
        )
    )

    return metodo


# ============================================================
# BLOQUE DE PRECIOS / PROMOCIONES
# ============================================================

def extraer_bloque_precios_pago(
    markdown
):

    if not markdown:

        return ""

    texto = markdown.replace(
        "\r\n",
        "\n"
    )

    texto = texto.replace(
        "\r",
        "\n"
    )

    # Cortamos antes de bloques que normalmente
    # ya no corresponden al precio principal.

    patrones_fin = [

        r"Ofertas\s+adicionales",

        r"Productos?\s+relacionados",

        r"También\s+te\s+puede\s+interesar",

        r"Información\s+del\s+producto",

        r"Especificaciones",
    ]

    posiciones = []

    for patron in patrones_fin:

        match = re.search(
            patron,
            texto,
            re.IGNORECASE
        )

        if match:

            posiciones.append(
                match.start()
            )

    if posiciones:

        texto = texto[
            :min(posiciones)
        ]

    return texto


# ============================================================
# EXTRAER PRECIOS VISIBLES
# ============================================================

def extraer_precios_visibles(
    texto
):

    resultados = []

    patron = re.compile(
        r"""
        (?:\*\*)?
        (?:\$|COP\s*)
        \s*
        ([\d\.,]+)
        (?:\*\*)?
        """,
        re.VERBOSE | re.IGNORECASE,
    )

    for match in patron.finditer(
        texto or ""
    ):

        numero = convertir_numero(
            match.group(1)
        )

        if numero is None:

            continue

        resultados.append(
            {
                "price": numero,

                "position":
                    match.start(),
            }
        )

    return resultados


# ============================================================
# EXTRAER ETIQUETAS DE PAGO
# ============================================================

def extraer_etiquetas_pago(
    markdown
):

    resultados = []

    if not markdown:

        return resultados

    # ========================================================
    # 1. LINKS / IMÁGENES MARKDOWN
    # ========================================================

    patron_links = re.compile(
        r"""
        \[
            ([^\]]+)
        \]
        \(
            [^\)]+
        \)
        """,
        re.VERBOSE | re.IGNORECASE,
    )

    for match in patron_links.finditer(
        markdown
    ):

        etiqueta = limpiar_texto(
            match.group(1)
        )

        metodo = (
            normalizar_nombre_pago(
                etiqueta
            )
        )

        if metodo is None:

            continue

        resultados.append(
            {

                "method": metodo,

                "position":
                    match.start(),

                "end_position":
                    match.end(),

                "source":
                    "markdown_link",
            }
        )

    # ========================================================
    # 2. TEXTO PLANO
    # ========================================================

    patron_texto = re.compile(
        r"(?im)^\s*\*?([A-Za-zÁÉÍÓÚáéíóúÑñ ]+)\*?\s*$"
    )

    for match in patron_texto.finditer(
        markdown
    ):

        etiqueta = limpiar_texto(
            match.group(1)
        )

        metodo = (
            normalizar_nombre_pago(
                etiqueta
            )
        )

        if metodo is None:

            continue

        resultados.append(
            {

                "method": metodo,

                "position":
                    match.start(),

                "end_position":
                    match.end(),

                "source":
                    "plain_text",
            }
        )

    # ========================================================
    # ORDEN
    # ========================================================

    resultados.sort(
        key=lambda item:
            item["position"]
    )

    # ========================================================
    # DEDUPLICACIÓN
    # ========================================================

    unicos = []

    vistas = set()

    for item in resultados:

        clave = (
            item["method"].casefold(),
            item["position"],
        )

        if clave in vistas:

            continue

        vistas.add(
            clave
        )

        unicos.append(
            item
        )

    return unicos


# ============================================================
# ASOCIAR MÉTODOS DE PAGO CON PRECIOS
# ============================================================

def extraer_medios_pago_desde_pagina(
    markdown
):

    if not markdown:

        return []

    bloque = (
        extraer_bloque_precios_pago(
            markdown
        )
    )

    if not bloque:

        return []

    precios = (
        extraer_precios_visibles(
            bloque
        )
    )

    etiquetas = (
        extraer_etiquetas_pago(
            bloque
        )
    )

    if (
        not precios
        or not etiquetas
    ):

        return []

    # Distancia máxima entre método y precio.
    DISTANCIA_MAXIMA = 350

    candidatos = []

    for etiqueta in etiquetas:

        posicion_metodo = (
            etiqueta["position"]
        )

        mejores_candidatos = []

        for precio in precios:

            posicion_precio = (
                precio["position"]
            )

            distancia = abs(
                posicion_metodo
                - posicion_precio
            )

            if (
                distancia
                >
                DISTANCIA_MAXIMA
            ):

                continue

            precio_despues = (
                posicion_precio
                >
                posicion_metodo
            )

            mejores_candidatos.append(
                {

                    "price": precio,

                    "distance":
                        distancia,

                    "price_after_method":
                        precio_despues,
                }
            )

        if not mejores_candidatos:

            continue

        candidato = min(
            mejores_candidatos,
            key=lambda item: (
                item["distance"],

                1
                if item[
                    "price_after_method"
                ]
                else 0,
            ),
        )

        candidatos.append(
            {

                "method":
                    etiqueta["method"],

                "price":
                    candidato[
                        "price"
                    ]["price"],

                "method_position":
                    posicion_metodo,

                "price_position":
                    candidato[
                        "price"
                    ]["position"],

                "distance":
                    candidato["distance"],
            }
        )

    if not candidatos:

        return []

    # ========================================================
    # RESOLVER COLISIONES
    # ========================================================

    candidatos.sort(
        key=lambda item: (

            item["distance"],

            item["method_position"],
        )
    )

    precios_utilizados = set()

    resultados = []

    for candidato in candidatos:

        precio_key = (
            candidato[
                "price_position"
            ]
        )

        if (
            precio_key
            in precios_utilizados
        ):

            continue

        precios_utilizados.add(
            precio_key
        )

        resultados.append(
            {

                "method":
                    candidato["method"],

                "total_price":
                    candidato["price"],
            }
        )

    # ========================================================
    # DEDUPLICACIÓN POR MÉTODO
    # ========================================================

    metodos_vistos = set()

    resultados_finales = []

    for item in resultados:

        clave = (
            item["method"]
            .casefold()
        )

        if clave in metodos_vistos:

            continue

        metodos_vistos.add(
            clave
        )

        resultados_finales.append(
            item
        )

    # ========================================================
    # ORDEN ORIGINAL
    # ========================================================

    posicion_por_metodo = {

        candidato["method"].casefold():
            candidato["method_position"]

        for candidato in candidatos
    }

    resultados_finales.sort(
        key=lambda item:
            posicion_por_metodo.get(
                item[
                    "method"
                ].casefold(),
                999999999,
            )
    )

    return resultados_finales


# ============================================================
# MÉTODOS DE PAGO DESDE CRAWL4AI
# ============================================================

def extraer_payment_methods(
    resultado
):

    if resultado is None:

        return []

    markdown = getattr(
        resultado,
        "markdown",
        None
    )

    if not isinstance(
        markdown,
        str
    ):

        return []

    return (
        extraer_medios_pago_desde_pagina(
            markdown
        )
    )


# ============================================================
# CATEGORÍA
# ============================================================

def extraer_categoria(
    producto
):

    category_id = producto.get(
        "categoryId"
    )

    categories = producto.get(
        "categories"
    )

    category = None

    if (
        isinstance(
            categories,
            list
        )
        and categories
    ):

        category = limpiar_texto(
            categories[-1]
        )

    elif isinstance(
        categories,
        str
    ):

        category = limpiar_texto(
            categories
        )

    return (

        (
            str(category_id)
            if category_id is not None
            else None
        ),

        category,
    )


# ============================================================
# RELEASE DATE
# ============================================================

def extraer_release_date(
    producto
):

    valor = (

        producto.get(
            "releaseDate"
        )

        or producto.get(
            "ReleaseDate"
        )
    )

    if valor is None:

        return None

    return limpiar_texto(
        valor
    )


# ============================================================
# REFERENCIA
# ============================================================

def extraer_product_reference(
    producto
):

    return (

        producto.get(
            "productReference"
        )

        or producto.get(
            "reference"
        )

        or producto.get(
            "refId"
        )
    )


# ============================================================
# CONSTRUIR PRODUCTO
# ============================================================

def construir_producto(
    producto,
    categoria_url,
    pagina,
    extracted_at,
):

    if not isinstance(
        producto,
        dict
    ):

        return None

    # --------------------------------------------------------
    # ID
    # --------------------------------------------------------

    product_id = (

        producto.get(
            "productId"
        )

        or producto.get(
            "id"
        )
    )

    if product_id is None:

        return None

    product_id = str(
        product_id
    ).strip()

    if not product_id:

        return None

    # --------------------------------------------------------
    # NOMBRE
    # --------------------------------------------------------

    nombre = limpiar_texto(
        producto.get(
            "productName"
        )
    )

    if not nombre:

        return None

    # --------------------------------------------------------
    # URL
    # --------------------------------------------------------

    link = (

        producto.get(
            "link"
        )

        or producto.get(
            "productUrl"
        )
    )

    if not link:

        link_text = producto.get(
            "linkText"
        )

        if link_text:

            link = (
                "/"
                + str(
                    link_text
                ).strip()
                + "/p"
            )

    if not link:

        return None

    product_url = (
        normalizar_product_url(
            link
        )
    )

    if not product_url:

        return None

    if not es_producto_url(
        product_url
    ):

        return None

    # --------------------------------------------------------
    # MARCA
    # --------------------------------------------------------

    brand = limpiar_texto(
        producto.get(
            "brand"
        )
    )

    brand_id = producto.get(
        "brandId"
    )

    if brand_id is not None:

        brand_id = str(
            brand_id
        )

    # --------------------------------------------------------
    # CATEGORÍA
    # --------------------------------------------------------

    (
        category_id,
        category,
    ) = extraer_categoria(
        producto
    )

    # --------------------------------------------------------
    # RELEASE DATE
    # --------------------------------------------------------

    release_date = (
        extraer_release_date(
            producto
        )
    )

    # --------------------------------------------------------
    # REFERENCIA
    # --------------------------------------------------------

    product_reference = (
        extraer_product_reference(
            producto
        )
    )

    if (
        product_reference
        is not None
    ):

        product_reference = str(
            product_reference
        )

    # --------------------------------------------------------
    # PRECIOS
    # --------------------------------------------------------

    (
        price,
        list_price,
        seller_info,
    ) = extraer_precios(
        producto
    )

    # --------------------------------------------------------
    # IMAGEN
    # --------------------------------------------------------

    image_url = extraer_imagen(
        producto
    )

    # --------------------------------------------------------
    # RESULTADO
    # --------------------------------------------------------

    resultado = {

        "source":
            SOURCE,

        "product_id":
            product_id,

        "product_name":
            nombre,

        "brand":
            (
                brand
                if brand
                else None
            ),

        "brand_id":
            brand_id,

        "product_reference":
            product_reference,

        "product_reference_code":
            product_reference,

        "category_id":
            category_id,

        "category":
            category,

        "price":
            price,

        "list_price":
            list_price,

        "currency":
            "COP",

        "image_url":
            image_url,

        "product_url":
            product_url,

        "source_category_url":
            categoria_url,

        "page":
            pagina,

        "release_date":
            release_date,

        "seller_id":
            (
                seller_info.get(
                    "seller_id"
                )
                if seller_info
                else None
            ),

        "seller_name":
            (
                seller_info.get(
                    "seller_name"
                )
                if seller_info
                else None
            ),

        "seller_available_quantity":
            (
                seller_info.get(
                    "available_quantity"
                )
                if seller_info
                else None
            ),

        # Se completa desde el PDP.
        "payment_methods":
            [],

        "extracted_at":
            extracted_at,
    }

    return resultado


# ============================================================
# ENRIQUECER PRODUCTO
# ============================================================

async def enriquecer_producto_con_pagina(
    crawler,
    producto,
):

    product_url = producto.get(
        "product_url"
    )

    if not product_url:

        return producto

    print(
        "[PDP] "
        f"{producto.get('product_name', '')}"
    )

    resultado = (
        await obtener_pagina_producto(
            crawler,
            product_url,
        )
    )

    if resultado is None:

        print(
            "[PDP] Sin datos de métodos "
            "de pago."
        )

        return producto

    payment_methods = (
        extraer_payment_methods(
            resultado
        )
    )

    producto[
        "payment_methods"
    ] = payment_methods

    if payment_methods:

        print(
            "[PDP] Métodos encontrados:"
        )

        for metodo in payment_methods:

            print(
                "      "
                f"{metodo['method']}: "
                f"${metodo['total_price']:,.0f}"
            )

    else:

        print(
            "[PDP] No se encontraron "
            "métodos promocionales "
            "verificables."
        )

    await asyncio.sleep(
        DELAY_ENTRE_PRODUCTOS
    )

    return producto


# ============================================================
# DEDUPLICACIÓN
# ============================================================

def deduplicar_productos(
    productos
):

    unicos = {}

    for producto in productos:

        product_id = producto.get(
            "product_id"
        )

        if not product_id:

            continue

        if (
            product_id
            not in unicos
        ):

            unicos[
                product_id
            ] = producto

            continue

        existente = unicos[
            product_id
        ]

        precio_existente = (
            convertir_numero(
                existente.get(
                    "price"
                )
            )
        )

        precio_nuevo = (
            convertir_numero(
                producto.get(
                    "price"
                )
            )
        )

        # Si encontramos un precio menor,
        # conservamos ese registro.

        if (
            precio_nuevo is not None
            and (
                precio_existente is None
                or precio_nuevo
                <
                precio_existente
            )
        ):

            registro_ganador = (
                producto
            )

            for campo, valor in (
                existente.items()
            ):

                if (
                    registro_ganador.get(
                        campo
                    )
                    in (
                        None,
                        "",
                        [],
                    )
                    and valor not in (
                        None,
                        "",
                        [],
                    )
                ):

                    registro_ganador[
                        campo
                    ] = valor

            unicos[
                product_id
            ] = registro_ganador

            continue

        # Completar campos faltantes
        # desde el nuevo registro.

        for campo, valor in (
            producto.items()
        ):

            if (
                existente.get(
                    campo
                )
                in (
                    None,
                    "",
                    [],
                )
                and valor not in (
                    None,
                    "",
                    [],
                )
            ):

                existente[
                    campo
                ] = valor

    return list(
        unicos.values()
    )


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


def imprimir_calidad(
    productos
):

    print()

    print("=" * 60)

    print(
        "[CALIDAD DE DATOS]"
    )

    print("=" * 60)

    total = len(
        productos
    )

    if total == 0:

        print(
            "Sin productos para evaluar."
        )

        return

    for campo in CAMPOS_CALIDAD:

        faltantes = sum(

            1

            for producto in productos

            if producto.get(
                campo
            )
            in (
                None,
                "",
                [],
            )
        )

        presentes = (
            total
            - faltantes
        )

        porcentaje = (
            presentes
            / total
        ) * 100

        print(
            f"  {campo:<32}"
            f"{presentes:>4}/{total:<4}"
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

    print(
        f"[CATEGORÍA "
        f"{categoria_index}/"
        f"{total_categorias}]"
    )

    print("=" * 60)

    print(
        categoria_url
    )

    productos_categoria = []

    for pagina in range(
        1,
        MAX_PAGINAS_POR_CATEGORIA + 1,
    ):

        print()

        print("-" * 60)

        print(
            "[PÁGINA]"
        )

        print(
            f"Categoría: "
            f"{categoria_url}"
        )

        print(
            f"Página:    "
            f"{pagina}"
        )

        print(f"URL:       {construir_url_pagina_categoria(categoria_url, pagina)}")


        print("-" * 60)

        inicio = time.perf_counter()

        data = await consultar_vtex(
            client,
            categoria_url,
            pagina,
        )

        duracion = (
            time.perf_counter()
            - inicio
        )

        print(
            "[VTEX] Productos recibidos: "
            f"{len(data)} "
            f"| {duracion:.2f}s"
        )

        if not data:

            print(
                "[PAGINACIÓN] Página "
                f"{pagina} sin productos."
            )

            break

        extracted_at = (
            obtener_timestamp_actual()
        )

        productos_validos = []

        for producto in data:

            normalizado = (
                construir_producto(
                    producto,
                    categoria_url,
                    pagina,
                    extracted_at,
                )
            )

            if normalizado is not None:

                productos_validos.append(
                    normalizado
                )

        print(
            "[RESULTADO] Productos válidos: "
            f"{len(productos_validos)}"
        )

        # ----------------------------------------------------
        # PDP
        # ----------------------------------------------------

        for producto in productos_validos:

            await (
                enriquecer_producto_con_pagina(
                    crawler,
                    producto,
                )
            )

        productos_categoria.extend(
            productos_validos
        )

        if (
            len(data)
            <
            PRODUCTOS_POR_PETICION
        ):

            print(
                "[PAGINACIÓN] Respuesta "
                "menor al tamaño de página."
            )

            break

        await asyncio.sleep(
            DELAY_ENTRE_PETICIONES
        )

    productos_categoria = (
        deduplicar_productos(
            productos_categoria
        )
    )

    print()

    print(
        "[CATEGORÍA] Productos únicos: "
        f"{len(productos_categoria)}"
    )

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

    RUTA_RAW.mkdir(
        parents=True,
        exist_ok=True,
    )

    payload = {

        "source":
            SOURCE,

        "start_url":
            DOMINIO_BASE,

        "extraction_started_at":
            extraction_started_at,

        "extraction_finished_at":
            extraction_finished_at,

        "timezone":
            "America/Bogota",

        "categories_processed":
            categorias_procesadas,

        "max_categories":
            MAX_CATEGORIAS,

        "max_pages_per_category":
            MAX_PAGINAS_POR_CATEGORIA,

        "products_per_request":
            PRODUCTOS_POR_PETICION,

        "products_found":
            len(productos),

        "products_unique":
            len(productos),

        "products":
            productos,
    }

    with open(
        RUTA_RAW_JSON,
        "w",
        encoding="utf-8",
    ) as archivo:

        json.dump(
            payload,
            archivo,
            ensure_ascii=False,
            indent=2,
        )

    return payload


# ============================================================
# MAIN
# ============================================================

async def main():

    extraction_started_at = (
        obtener_timestamp_actual()
    )

    print()

    print("=" * 60)

    print(
        "PREZIO - SCRAPER JUMBO"
    )

    print("=" * 60)

    print(
        "Inicio extracción: "
        f"{extraction_started_at}"
    )

    print(
        "URL inicial: "
        f"{DOMINIO_BASE}"
    )

    print(
        "Máximo categorías: "
        f"{MAX_CATEGORIAS}"
    )

    print(
        "Máximo páginas/categoría: "
        f"{MAX_PAGINAS_POR_CATEGORIA}"
    )

    print(
        "Productos por petición: "
        f"{PRODUCTOS_POR_PETICION}"
    )

    print(
        "Endpoint VTEX: "
        f"{VTEX_SEARCH_ENDPOINT}"
    )

    print(
        "Concurrencia HTTP: "
        f"{CONCURRENCIA}"
    )

    print(
        "Métodos de pago: "
        "PDP REAL DE JUMBO"
    )

    print(
        "Filtro de métodos: "
        "LISTA BLANCA"
    )

    print(
        "Zona horaria: "
        "America/Bogota"
    )

    print()

    # ========================================================
    # BROWSER
    # ========================================================

    browser_config = BrowserConfig(

        headless=True,

        verbose=False,

        user_agent=HEADERS[
            "User-Agent"
        ],
    )

    crawler_config = CrawlerRunConfig(

        cache_mode=CacheMode.BYPASS,

        page_timeout=
            PRODUCT_PAGE_TIMEOUT,

        magic=True,

        simulate_user=True,

        override_navigator=True,
    )

    async with AsyncWebCrawler(
        config=browser_config
    ) as crawler:

        # ====================================================
        # FASE 1
        # ====================================================

        categorias = (
            await descubrir_categorias(
                crawler
            )
        )

        if not categorias:

            print()

            print(
                "[ERROR] No se encontraron "
                "categorías válidas."
            )

            return

        # ====================================================
        # FASE 2
        # ====================================================

        productos_totales = []

        limits = httpx.Limits(

            max_connections=
                CONCURRENCIA,

            max_keepalive_connections=
                CONCURRENCIA,
        )

        timeout = httpx.Timeout(
            HTTP_TIMEOUT
        )

        async with httpx.AsyncClient(

            headers=HEADERS,

            timeout=timeout,

            limits=limits,

            follow_redirects=True,

        ) as client:

            for indice, categoria_url in (
                enumerate(
                    categorias,
                    start=1,
                )
            ):

                productos_categoria = (
                    await procesar_categoria(
                        client,
                        crawler,
                        categoria_url,
                        indice,
                        len(categorias),
                    )
                )

                productos_totales.extend(
                    productos_categoria
                )

        # ====================================================
        # DEDUPLICACIÓN GLOBAL
        # ====================================================

        productos_totales = (
            deduplicar_productos(
                productos_totales
            )
        )

        # ====================================================
        # FIN
        # ====================================================

        extraction_finished_at = (
            obtener_timestamp_actual()
        )

        # ====================================================
        # RESUMEN
        # ====================================================

        print()

        print("=" * 60)

        print(
            "[RAW]"
        )

        print("=" * 60)

        print(
            "Inicio extracción: "
            f"{extraction_started_at}"
        )

        print(
            "Fin extracción:    "
            f"{extraction_finished_at}"
        )

        print(
            "Categorías procesadas: "
            f"{len(categorias)}"
        )

        print(
            "Registros encontrados: "
            f"{len(productos_totales)}"
        )

        print(
            "Registros únicos: "
            f"{len(productos_totales)}"
        )

        imprimir_calidad(
            productos_totales
        )

        # ====================================================
        # GUARDAR
        # ====================================================

        guardar_raw(
            productos_totales,
            len(categorias),
            extraction_started_at,
            extraction_finished_at,
        )

        print()

        print(
            "Archivo: "
            f"{RUTA_RAW_JSON}"
        )

        print()

        print("=" * 60)

        print(
            "[FIN]"
        )

        print("=" * 60)


# ============================================================
# EJECUCIÓN
# ============================================================

if __name__ == "__main__":

    asyncio.run(
        main()
    )