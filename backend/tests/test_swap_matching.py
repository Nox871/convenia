from app.core.swap_matching import (
    Producto,
    es_mas_barato,
    es_mismo_producto,
    extraer_cantidad,
    palabras_base,
    puede_sustituir,
    tamano_similar,
)


def _p(nombre: str, marca: str | None = None) -> Producto:
    return Producto(nombre=nombre, marca=marca)


def test_extrae_cantidad_y_la_lleva_a_una_unidad_base():
    assert extraer_cantidad("Leche FRESCAMPO entera UHT bolsa (900 ml)").valor == 900
    assert extraer_cantidad("Arroz DIANA (1 kg)").valor == 1000
    assert extraer_cantidad("Arroz DIANA (500 gr)").dimension == "peso"
    assert extraer_cantidad("Papa Capira 1 und").dimension == "conteo"
    assert extraer_cantidad("Producto sin tamaño") is None


def test_palabras_base_quitan_marca_y_cantidad():
    assert palabras_base("Leche FRESCAMPO entera UHT bolsa (900 ml)", "FRESCAMPO") == [
        "leche", "entera", "uht", "bolsa",
    ]


def test_un_sustituto_es_de_la_misma_clase_y_tamano_parecido():
    original = _p("Leche FRESCAMPO entera UHT bolsa (900 ml)", "FRESCAMPO")
    otra_marca = _p("Leche COLANTA entera UHT bolsa (900 ml)", "COLANTA")

    assert puede_sustituir(original, otra_marca)


def test_no_sustituye_un_producto_de_otro_tipo():
    leche_entera = _p("Leche FRESCAMPO entera UHT bolsa (900 ml)", "FRESCAMPO")
    deslactosada = _p("Leche COLANTA deslactosada semidescremada (900 ml)", "COLANTA")
    jabon = _p("Jabón Dove barra leche (90 gr)", "Dove")

    assert not puede_sustituir(leche_entera, deslactosada)
    assert not puede_sustituir(leche_entera, jabon)


def test_no_sustituye_uno_de_tamano_muy_distinto():
    grande = _p("Leche FRESCAMPO entera UHT bolsa (1100 ml)", "FRESCAMPO")
    chica = _p("Leche COLANTA entera UHT bolsa (250 ml)", "COLANTA")

    assert not puede_sustituir(grande, chica)


def test_el_mismo_producto_en_otro_supermercado_no_es_un_sustituto():
    a = _p("Arroz DIANA blanco premium (1000 gr)", "DIANA")
    b = _p("Arroz Diana blanco premium 1 kg", "Diana")

    assert es_mismo_producto(a, b)
    assert not puede_sustituir(a, b)


def test_con_cantidad_solo_en_uno_no_se_asume_que_sea_del_mismo_tamano():
    assert not tamano_similar(extraer_cantidad("Arroz (500 gr)"), None)
    assert tamano_similar(None, None)


def test_un_ahorro_de_centavos_no_vale_un_cambio():
    assert es_mas_barato(10000, 9000)
    assert not es_mas_barato(10000, 9800)
    assert not es_mas_barato(10000, 10000)
    assert not es_mas_barato(0, 0)
