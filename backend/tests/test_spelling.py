import pytest

from app.core.spelling import corregir_palabra, distancia, sugerir_busqueda

VOCAB = {"arroz": 900, "arroces": 4, "aroma": 20, "leche": 700, "lechuga": 80,
         "jabon": 300, "detergente": 120, "atun": 90, "azucar": 150, "cafe": 400,
         "arros": 1, "diana": 60, "pollo": 200}


@pytest.mark.parametrize("escrito,esperado", [
    ("aroz", "arroz"), ("arros", "arroz"), ("arrroz", "arroz"), ("lache", "leche"),
    ("detergent", "detergente"), ("asucar", "azucar"), ("jabom", "jabon"),
])
def test_corrige_errores_de_tipeo(escrito, esperado):
    assert corregir_palabra(escrito, VOCAB) == esperado


@pytest.mark.parametrize("bien", ["arroz", "leche", "diana", "pollo"])
def test_palabras_bien_escritas_no_se_tocan(bien):
    assert corregir_palabra(bien, VOCAB) is None


def test_palabra_rara_que_no_se_parece_a_nada_no_se_inventa():
    assert corregir_palabra("xylofono", VOCAB) is None


def test_un_error_del_catalogo_no_valida_el_error_del_usuario():
    # "arros" aparece una sola vez en el catálogo: no cuenta como palabra conocida
    assert corregir_palabra("arros", VOCAB) == "arroz"


def test_sugerencia_de_frase_completa_y_tildes():
    assert sugerir_busqueda("Aroz Diana", VOCAB) == "arroz diana"
    assert sugerir_busqueda("café", VOCAB) is None
    assert sugerir_busqueda("arroz diana", VOCAB) is None
    assert sugerir_busqueda("", VOCAB) is None


def test_numeros_y_palabras_cortas_se_dejan():
    assert sugerir_busqueda("arroz 500 g", VOCAB) is None


def test_distancia_con_corte():
    assert distancia("aroz", "arroz", 1) == 1
    assert distancia("gato", "arroz", 1) > 1
