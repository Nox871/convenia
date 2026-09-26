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
]

# Palabras de empaque que pueden encabezar un nombre sin decir qué es.
_EMPAQUES = {"paquete", "pack", "combo", "tripack", "caja", "cubeta"}

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
    cafe chocolate chocolates chocolatina cacao cocoa pan tostadas bocadillo
    arequipe mermelada galleta galletas arepa arepas
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
    categoria = _CABEZA.get(normalizado.split(" ", 1)[0])
    # Una fruta, verdura o grano "congelado" ya no es fresco ni de despensa.
    if categoria in (FRUTAS, DESPENSA) and _CONGELADO.search(normalizado):
        return CONGELADOS
    return categoria
