import re

import pytest

from app.core.query_parser import interpretar, sin_tildes


def _coincide(consulta, nombre):
    c = interpretar(consulta)
    assert c.cantidad_regex is not None
    return re.search(c.cantidad_regex, sin_tildes(nombre)) is not None


@pytest.mark.parametrize("q,palabras", [
    ("huevos 30 und", ["huevos"]),
    ("30 unidades huevo", ["huevo"]),
    ("café 500", ["cafe"]),
    ("leche 1 litro", ["leche"]),
    ("Arroz Diana 500g", ["arroz", "diana"]),
    ("esponja bon", ["esponja", "bon"]),
    ("aceite de oliva", ["aceite", "oliva"]),
    ("jabón x 3", ["jabon"]),
])
def test_separa_las_palabras_de_la_presentacion(q, palabras):
    assert interpretar(q).palabras == palabras


def test_sin_numeros_no_hay_filtro_de_cantidad():
    c = interpretar("arroz diana")
    assert c.cantidad_regex is None and c.cantidad_texto is None


@pytest.mark.parametrize("nombre", [
    "Huevos AAA NAPOLES rojo (30 und)",
    "Huevos Santa Reyes x30 unidades",
    "HUEVO ROJO AA x 30",
])
def test_huevos_30_encuentra_presentaciones_de_30(nombre):
    assert _coincide("huevos 30 und", nombre)


@pytest.mark.parametrize("nombre", [
    "Huevos AAA NAPOLES rojo (12 und)",
    "Huevos x 180 und",      # 180 no es 30
    "Huevos 130 g",
    "Huevos 0,30 kg",
])
def test_huevos_30_no_confunde_otras_presentaciones(nombre):
    assert not _coincide("huevos 30 und", nombre)


@pytest.mark.parametrize("nombre", ["Café SELLO ROJO molido (500 gr)", "Café x 500 g", "Café 0,5 kg", "Cafe 500g"])
def test_cafe_500_acepta_gramos_y_su_equivalente_en_kilos(nombre):
    assert _coincide("café 500", nombre)


@pytest.mark.parametrize("nombre", ["Café SELLO ROJO molido (250 gr)", "Café 1500 gr", "Café 5000 g"])
def test_cafe_500_no_confunde_250_ni_1500(nombre):
    assert not _coincide("café 500", nombre)


def test_unidades_equivalentes_litros_y_mililitros():
    assert _coincide("leche 1 litro", "Leche COLANTA entera (1000 ml)")
    assert _coincide("leche 1 litro", "Leche entera 1 L")
    assert _coincide("leche 1 litro", "Leche entera 1 lt")
    assert not _coincide("leche 1 litro", "Leche entera (900 ml)")
    assert _coincide("arroz 1 kg", "Arroz Diana 1000 gr")
    assert _coincide("arroz 2 libras", "Arroz Diana 1000 gr")


def test_decimales():
    assert _coincide("agua 1.5 l", "Agua cristal 1,5 L")
    assert _coincide("agua 1,5 litros", "Agua cristal 1500 ml")


def test_consulta_vacia_o_solo_numeros():
    assert interpretar("").palabras == []
    assert interpretar("500").palabras == []
    assert interpretar("500").cantidad_regex is not None


from app.core.query_parser import termino_de_busqueda  # noqa: E402


@pytest.mark.parametrize("q,esperado", [
    ("café", ("cafe", "Café")),
    ("Cafe", ("cafe", "Cafe")),
    ("  ARROZ  ", ("arroz", "Arroz")),
    ("huevos 30 und", ("huevos", "Huevos")),
    ("leche entera", ("leche entera", "Leche entera")),
])
def test_termino_de_busqueda_clave_y_texto_a_mostrar(q, esperado):
    assert termino_de_busqueda(q) == esperado


@pytest.mark.parametrize("q", ["", "  ", "ab", "123", "500", "x" * 60, "30 und"])
def test_busquedas_que_no_cuentan(q):
    assert termino_de_busqueda(q) is None


from app.core.query_parser import patron_de_palabra  # noqa: E402


def _encuentra(palabra, nombre):
    return re.search(patron_de_palabra(palabra), sin_tildes(nombre)) is not None


@pytest.mark.parametrize("nombre", ["Pan tajado Bimbo", "Pan Perro BIMBO x6und", "Mini pan de queso", "PAN BLANCO 500 g", "Panes surtidos"])
def test_pan_encuentra_pan(nombre):
    assert _encuentra("pan", nombre)


@pytest.mark.parametrize("nombre", [
    "Paño Absorbente Tidy House", "Pañuelo Facial Rendy", "Empanada con Carne Toastatas",
    "Acondicionador Pantene", "Queso Ibérico Viva España", "Panela cuadrada", "Pandebono",
])
def test_pan_no_encuentra_lo_que_solo_lo_contiene(nombre):
    assert not _encuentra("pan", nombre)


def test_palabras_cortas_aceptan_plural_pero_no_otras_palabras():
    assert _encuentra("papa", "Papas fritas Margarita")
    assert not _encuentra("sal", "Salsa de tomate")
    assert not _encuentra("sal", "Salchicha ranchera")
    assert _encuentra("sal", "Sal REFISAL alta pureza")


def test_palabras_largas_aceptan_prefijo_pero_no_el_medio():
    assert _encuentra("huevo", "Huevos AAA rojo (12 und)")
    assert _encuentra("leche", "Lechera condensada")
    assert not _encuentra("cafe", "Descafeinado instantáneo")
    assert _encuentra("cafe", "Café Sello Rojo molido")


def test_texto_que_no_es_una_palabra_no_tiene_patron():
    assert patron_de_palabra("") is None
    assert patron_de_palabra("a.b(") is None


def test_plural_largo_encuentra_el_singular():
    assert _encuentra("huevos", "Huevo de Codorniz Sol Naciente 24 Und")
    assert _encuentra("huevos", "Huevos AAA rojo (12 und)")
    assert _encuentra("jabones", "Jabón de barra Rey")
    assert _encuentra("gaseosas", "Gaseosa Coca Cola 1,5 L")
    # sin falsos positivos nuevos
    assert not _encuentra("huevos", "Huevera plástica 12 espacios")
    assert not _encuentra("leches", "Lechuga crespa")
