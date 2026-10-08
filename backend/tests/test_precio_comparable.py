import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from shared.precio_comparable import es_precio_no_comparable, tiene_cantidad_declarada

RUTA = "/Supermercado/Pollo, Carne y Pescado/Carnes De Res Y Otras/"


def test_lomo_a_500_sin_peso_no_es_comparable():
    assert es_precio_no_comparable("Res Lomo Fino/Biche/Solomo sin Corbata", RUTA, 500)


def test_hueso_de_cerdo_a_2500_sin_peso_no_es_comparable():
    assert es_precio_no_comparable("Hueso de Cerdo Blanco", RUTA, 2500)


def test_pieza_cara_sin_peso_se_conserva():
    assert not es_precio_no_comparable("Lomo Fino de Res Paraguayo", RUTA, 83979)


def test_con_peso_declarado_se_conserva_aunque_sea_barato():
    assert tiene_cantidad_declarada("Pollo desmechado 300g")
    assert not es_precio_no_comparable("Pollo desmechado 300g", RUTA, 4500)


def test_no_carnes_no_se_tocan():
    assert not es_precio_no_comparable("Banano", "/Supermercado/Frutas y Verduras/", 2500)


def test_sin_precio():
    assert not es_precio_no_comparable("Hueso de Cerdo Blanco", RUTA, None)
