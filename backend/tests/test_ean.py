import pytest

from shared.ean import normalizar_ean


@pytest.mark.parametrize("valor", ["7702137302073", "7702213411569", "7702137007701", 7702137186642])
def test_eans_reales_de_fabricante_son_validos(valor):
    assert normalizar_ean(valor) is not None


@pytest.mark.parametrize("valor", [
    "7702137302074",   # dígito verificador incorrecto
    "2000000012345",   # prefijo 2: uso interno / peso variable
    "0000000000000", "1111111111111",
    "123", "", None, "abc",
])
def test_codigos_no_utilizables_se_ignoran(valor):
    assert normalizar_ean(valor) is None


def test_upc12_y_ean13_son_la_misma_clave():
    assert normalizar_ean("012345678905") == normalizar_ean("0012345678905")


def test_se_limpian_espacios_y_guiones():
    assert normalizar_ean(" 7702137302073 ") == normalizar_ean("7702137302073")
    assert normalizar_ean("7702-137-302073") == normalizar_ean("7702137302073")
