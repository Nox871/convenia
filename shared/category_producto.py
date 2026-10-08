"""Categoría de un PRODUCTO a partir de su nombre.

Los pasillos de los supermercados son inconsistentes: Éxito ubica la leche
de coco en "Pescados y mariscos" y las arepas entre los lácteos refrigerados;
otros ponen el yogur entre las bebidas y el jamón entre los lácteos. Heredar
el pasillo produce categorías sin sentido para quien navega la app.

El nombre de un producto casi siempre empieza por lo que ES ("Leche ...",
"Arepas ...", "Yogurt ..."), así que aquí se clasifica por esa primera
palabra, con unas pocas frases especiales que la contradicen ("leche de
coco", "papas fritas"). Si el nombre no alcanza (marca primero, palabra rara),
devuelve None y quien llama usa la categoría del pasillo como respaldo.

Sólo stdlib, igual que `category_filter`, para poder importarse desde el
backend, el scraper y el ETL.
"""
from __future__ import annotations

import re
import unicodedata
from functools import lru_cache

from .category_filter import etiqueta_amigable
from functools import lru_cache

DESPENSA = "Despensa"
PANADERIA = "Panadería y desayuno"
BEBIDAS = "Bebidas"
LACTEOS = "Lácteos y huevos"
CARNES = "Carnes y embutidos"
CONGELADOS = "Congelados"
FRUTAS = "Frutas y verduras"
SNACKS = "Snacks"
ASEO = "Aseo y cuidado personal"
PERSONAL = ASEO  # aseo del hogar y cuidado personal son una sola categoría

# Frases que contradicen a la primera palabra. Se evalúan primero, en orden,
# sobre el nombre normalizado (minúsculas, sin tildes ni signos).
_FRASES: list[tuple[str, str]] = [
    (r"^papas? .*\b(prefrit[ao]s?|pre fritas?|congelad[ao]s?)\b", CONGELADOS),
    (r"^alimento .*\bpolvo\b", DESPENSA),
    (r"^alimento (de )?(soya|almendras?|avena|toning)", DESPENSA),
    (r"^crem a de coco|^crema (de )?coco", DESPENSA),
    (r"^base (para )?(salsa|sopa|guiso)", DESPENSA),
    (r"^kit refresc", DESPENSA),
    (r"^tomates? en (pure|salsa|trozos)", DESPENSA),
    (r"^barra (de )?(cereal|granola|proteina|con)", SNACKS),
    (r"^mr\b", ASEO),
    (r"^leche de coco", DESPENSA),
    (r"^crema de coco", DESPENSA),
    (r"^crema de leche", LACTEOS),
    (r"^crema dental", PERSONAL),
    (r"^papas? (a la )?francesa", CONGELADOS),
    (r"^papas? .*\b(fritas?|fosforitos|margarita|chips)\b", SNACKS),
    (r"^lomitos? de atun", DESPENSA),
    (r"^capsulas?", PANADERIA),
    (r"^papel (higienico|de cocina|toalla)", ASEO),
    (r"^huevo de (solomo|aldana|pierna)", CARNES),
    (r"^pepino de res", CARNES),
    (r"^manteca", DESPENSA),
    (r"^avena (alpina|colanta)", BEBIDAS),
    (r"^papas? (en casco|airfryer)", CONGELADOS),
    (r"^ajo .*\b(polvo|granulado|natural)\b", DESPENSA),
    (r"^tomate .*\blata\b", DESPENSA),
    (r"^(frijol|arveja) desgranad", FRUTAS),
    (r"^vinagre de limpieza", ASEO),
    (r"\bultralimp", ASEO),
    (r"^ajo (el rey|badia|speciaria|specia)", DESPENSA),
    (r"^(refresco|bebida|mezcla|jugo)\b(?!.*\b(ml|lt|l|litros?)\b).*\b[0-9]+ ?(g|gr|grs|gramos)\b", DESPENSA),
    (r"^mini chuzos", CARNES),
    (r"^mini (viennoiseria|croissant|miti|ponque|ponques|donas?|pan|panes)", PANADERIA),
    (r"^ajo \b.*\b(condimento|molido|polvo|granulado|sazonador|especias?|pasta|salsa)\b", DESPENSA),
]

# Marcas y expresiones inequívocas: valen en CUALQUIER parte del nombre aunque la
# primera palabra engañe ("MANZANA ... POSTOBON" es una gaseosa, no una fruta).
_SENALES_FUERTES: list[tuple[str, str]] = [
    (r"\b(postobon|coca cola|pepsi|sprite|fanta|colombiana|gaseosa|gatorade|powerade|red bull|monster)\b", BEBIDAS),
    (r"\b(refresco|bebida|jugo|granizado|limonada)\b.*\bpolvo\b|\bpolvo\b.*\b(refresco|bebida|jugo|granizado)\b", DESPENSA),
    (r"\b(el rey|badia|tricondor|alinoli|dona gallina|granaroma)\b", DESPENSA),
    (r"\b(cheetos|doritos|chitos|todo rico|detodito|de todito|pringles|natuchips|takis|boliqueso|choclitos|popetas)\b", SNACKS),
    (r"\b(bon bon bum|halls|mentos|trident)\b", SNACKS),
]
# Palabras que dicen qué es el producto, pero sólo se usan cuando la PRIMERA palabra
# no lo dice ("Caramelos ..." sí; "Bebida de almendras" o "Jabón de almendra" no).
_SENALES_SI_CABEZA_DESCONOCIDA: list[tuple[str, str]] = [
    (r"\b(caramelo|caramelos|chicle|chicles|bombon|bombones|gomitas|gomas|paleta|paletas|chupeta|chupetas|chokis|masmelos|malvaviscos|crispetas|snack|snacks)\b", SNACKS),
    (r"\bbolitas? de chocolate\b", SNACKS),
    (r"\b(frutos secos|nueces|almendras?|pistachos?|maranon)\b", SNACKS),
]
_SENALES_FUERTES_C = [(re.compile(patron), categoria) for patron, categoria in _SENALES_FUERTES]
_SENALES_SUAVES_C = [(re.compile(patron), categoria) for patron, categoria in _SENALES_SI_CABEZA_DESCONOCIDA]

# Palabras de empaque que pueden encabezar un nombre sin decir qué es.
_EMPAQUES = {"paquete", "pack", "combo", "tripack", "caja", "cubeta", "bolsa"}

# Primera palabra -> categoría.
_CABEZA: dict[str, str] = {}


def _registrar(categoria: str, palabras: str) -> None:
    for palabra in palabras.split():
        _CABEZA[palabra] = categoria


_registrar(DESPENSA, """
    arroz aceite pasta pastas spaghetti penne fideos salsa azucar frijol
    frijoles harina sal vinagre avena lenteja lentejas gelatina maiz cereal
    garbanzo caldo mayonesa panela mostaza canela paprika sopa arveja granola
    bicarbonato miel oregano tortilla tortillas color atun sardina
    sardinas saltinas
""")
_registrar(PANADERIA, """
    cafe chocolate chocolates cacao cocoa pan tostadas bocadillo
    arequipe mermelada arepa arepas
""")
_registrar(BEBIDAS, """
    gaseosa soda agua bebida refresco jugo jugos te malta nectar infusion
    aromatica pony milo
""")
_registrar(LACTEOS, """
    leche queso quesito quesillo yogurt yogur huevos huevo mantequilla
    esparcible margarina cuajada suero kefir kumis
""")
_registrar(CARNES, """
    carne filete filetes pechuga costilla hamburguesa lomo molida chuleta
    camaron muslo muslos tilapia tocino tocineta higado nuggets contramuslo
    salmon lomito milanesa pierna churrasco pollo alas alitas trozos trucha
    bife presas chorizo salchicha salchichon jamon mortadela morcilla pernil
    solomito corazones gallina callo posta morrillo sobrebarriga espinazo
    molleja pezuna medallones pecho caderita bondiola punta chuzos muchacho
""")
_registrar(CONGELADOS, "pulpa croqueta hashbrown pizza deditos")
_registrar(FRUTAS, """
    papa tomate lechuga manzana cebolla arandanos pepino naranja ajo champinon
    limon mango espinaca zanahoria platano aguacate cilantro uva pimenton apio
    yuca papaya brocoli kiwi ahuyama sandia mazorca pina zarzamora banano melon
    ciruela pera peras guineo perejil maracuya cogollito cogollo ensalada
    remolacha acelga pitahaya granadilla lulo habichuela zapayo berenjena
    arracacha esparragos repollo uchuva coliflor murrapo zapote guayaba
    durazno mandarina coco
""")
_registrar(SNACKS, "pasabocas mani platanitos rosquitas maicitos papas")
_registrar(ASEO, """
    papel detergente lavaloza suavizante limpiapisos blanqueador esponja
    jabon toalla toallas servilleta servilletas lavaplatos limpiador quitamanchas panos pano
    desengrasante limpiavidrios ambientador guante guantes
""")
_registrar(PERSONAL, "cepillo maquina seda alcohol enjuague pomos")
_registrar(ASEO, """
    shampoo champu acondicionador desodorante limpia lava gel tratamiento cuchilla
    protectores toallitas desinfectante esponjas esponjilla axion dove crema_
""")
_registrar(PANADERIA, "ponque ponques mogolla rapiditas brownie buenazo croissant")
_registrar(BEBIDAS, "coca gatorade")
_registrar(SNACKS, "chocolatina chocolatinas galleta galletas")
_registrar(LACTEOS, "alimento")
_registrar(CARNES, """
    mejillones almeja almejas mojarra bagre pargo postas cubos hueso tapa chata cola
    centro loncha calamar pulpo langostinos atun_fresco
""")
_registrar(CONGELADOS, "anillos")


_registrar(DESPENSA, """
    endulzante aceitunas sazonador condimentos condimento pimienta vinagreta compota
    nuez nueces semillas comino curry granaroma
""")
_registrar(PANADERIA, "torta tortas")
_registrar(SNACKS, "barquillos chicharron chicharrones barra")
_registrar(BEBIDAS, "beb zumo")
_registrar(CARNES, "res pez")
_registrar(LACTEOS, "postre alpin")

# Ambiguas a propósito (el pasillo decide): "crema" (de leche, dental, corporal),
# "bolsa", "mezcla", "x", "mora" y "fresa" (frescas vs. congeladas).


def _normalizar(texto: str) -> str:
    sin_tildes = unicodedata.normalize("NFD", texto.lower())
    sin_tildes = "".join(c for c in sin_tildes if unicodedata.category(c) != "Mn")
    return " ".join(re.findall(r"[a-z0-9]+", sin_tildes))


_FRASES_COMPILADAS = [(re.compile(patron), categoria) for patron, categoria in _FRASES]
_CONGELADO = re.compile(r"\bcong(elad[oa]s?)?\b")


@lru_cache(maxsize=16384)
def categoria_por_nombre(nombre: str | None) -> str | None:
    """Etiqueta amigable según el nombre del producto, o None si el nombre
    no permite decidir."""
    if not nombre:
        return None
    normalizado = _normalizar(nombre)
    # "Paquete Arepas ...": el empaque no dice qué es; se mira lo que sigue.
    while True:
        palabras = normalizado.split(" ", 1)
        if len(palabras) == 2 and palabras[0] in _EMPAQUES:
            normalizado = palabras[1]
        else:
            break
    if not normalizado:
        return None
    for patron, categoria in _FRASES_COMPILADAS:
        if patron.search(normalizado):
            return categoria
    for patron, categoria in _SENALES_FUERTES_C:
        if patron.search(normalizado):
            return categoria
    cabeza = _CABEZA.get(normalizado.split(" ", 1)[0])
    if cabeza is None:
        for patron, categoria in _SENALES_SUAVES_C:
            if patron.search(normalizado):
                return categoria
    categoria = _CABEZA.get(normalizado.split(" ", 1)[0])
    # Una fruta, verdura o grano "congelado" ya no es fresco ni de despensa.
    if categoria in (FRUTAS, DESPENSA) and _CONGELADO.search(normalizado):
        return CONGELADOS
    return categoria


_RAICES_GENERICAS = {"supermercado", "mercado"}


def _es_pasillo_generico(ruta_categoria: str | None) -> bool:
    """True si la ruta es vacía o sólo la raíz del sitio (sin subcategorías)."""
    segmentos = [_normalizar(x) for x in (ruta_categoria or "").split("/") if x.strip()]
    return all(x in _RAICES_GENERICAS for x in segmentos)


@lru_cache(maxsize=4096)
def _etiqueta_por_pasillo(ruta_categoria: str | None) -> str | None:
    # Hay unos pocos cientos de pasillos distintos frente a miles de
    # productos: se clasifica cada pasillo una vez, no una vez por producto.
    return etiqueta_amigable(ruta_categoria)


def categoria_de_producto(nombre: str | None, ruta_categoria: str | None) -> str | None:
    """Categoría amigable de un producto. Se decide por el NOMBRE (lo que el
    producto es) y sólo si no alcanza se usa el pasillo del supermercado, que
    es inconsistente (ej. leche de coco en "Pescados y mariscos"). Si el
    pasillo no pertenece al alcance de canasta familiar, el producto queda
    fuera aunque el nombre sugiera una categoría.

    Se usa tanto para mostrarle la categoría al consumidor (backend) como
    para AGRUPAR productos candidatos a homologar (`etl/homologacion/run.py`):
    agrupar por esta etiqueta -- en vez de por el pasillo crudo -- evita que
    dos huevos iguales queden en grupos distintos solo porque un supermercado
    los archiva bajo "Lácteos" y el otro bajo "Huevos"."""
    por_pasillo = _etiqueta_por_pasillo(ruta_categoria)
    if por_pasillo is None:
        # Un pasillo que es sólo la raíz del sitio ("/Supermercado/") no dice
        # nada: ahí Jumbo archiva leche y café sueltos. Se decide por el nombre,
        # y si el nombre tampoco alcanza, queda fuera.
        if _es_pasillo_generico(ruta_categoria):
            return categoria_por_nombre(nombre)
        return None
    return categoria_por_nombre(nombre) or por_pasillo
