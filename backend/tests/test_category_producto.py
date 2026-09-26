import pytest

from app.core.category_bucket import categoria_de_producto
from shared.category_producto import categoria_por_nombre


@pytest.mark.parametrize(
    "nombre, esperado",
    [
        ("LECHE DE COCO VITAMAR 250 gr", "Despensa"),
        ("Leche De Coco ANTILLANA 250 gr", "Despensa"),
        ("Leche deslactosada FRESCAMPO UHT bolsa (900 ml)", "Lácteos y huevos"),
        ("Crema de Leche Larga Vida 200 gr", "Lácteos y huevos"),
        ("Arepas blancas EKONO tela x5und (400 gr)", "Panadería y desayuno"),
        ("Yogurt BABYGO vainilla vaso (107 ml)", "Lácteos y huevos"),
        ("Jamón ZENU sánduche x11 tajadas (230 gr)", "Carnes y embutidos"),
        ("Salchicha ZENU americana (450 gr)", "Carnes y embutidos"),
        ("Papas SUPER RICAS fritas fosforitos (160 gr)", "Snacks"),
        ("Papas a la Francesa Toastatas", "Congelados"),
        ("Papa Capira 1 und", "Frutas y verduras"),
        ("Atún ALAMAR en agua (91 gr)", "Despensa"),
        ("Gaseosa Coca Cola ZERO botella (600 ml)", "Bebidas"),
        ("Crema Dental Tri Acción Colgate 100 Ml", "Aseo y cuidado personal"),
        ("Paquete Arepas Sonsoneña maíz (5 und)", "Panadería y desayuno"),
        ("PASTA ULTRALIMP SANIT ANTIB 50G X3", "Aseo y cuidado personal"),
        ("Ajo El Rey bolsa x55g", "Despensa"),
        ("Huevo de solomo fresco", "Carnes y embutidos"),
        ("Pepino de res o tableado fresco", "Carnes y embutidos"),
        ("Brocoli Congelado Cooltivo 500 G", "Congelados"),
        ("Ajo EL REY en polvo (55 gr)", "Despensa"),
        ("Papas en Casco Toastatas 500 Gr", "Congelados"),
        ("Manteca de Cerdo PRACTICA", "Despensa"),
        ("Jabón de barra REY azul (300 gr)", "Aseo y cuidado personal"),
        ("Papel higiénico EKONO triple hoja (396 mts)", "Aseo y cuidado personal"),
    ],
)
def test_categoria_por_nombre(nombre, esperado):
    assert categoria_por_nombre(nombre) == esperado


def test_nombre_ambiguo_no_decide():
    # "Crema" puede ser de leche, dental o corporal: que decida el pasillo.
    assert categoria_por_nombre("Crema NIVEA hidratante (200 ml)") is None
    assert categoria_por_nombre("") is None
    assert categoria_por_nombre(None) is None


def test_el_nombre_manda_sobre_el_pasillo_del_supermercado():
    pasillo = "/Mercado/Pollo, carne y pescado/Pescados Y Mariscos/"
    assert categoria_de_producto("Leche De Coco ANTILLANA 250 gr", pasillo) == "Despensa"


def test_sin_nombre_util_se_usa_el_pasillo():
    pasillo = "/Mercado/Pollo, carne y pescado/Pescados Y Mariscos/"
    assert categoria_de_producto("Marca rara sin categoria", pasillo) == "Carnes y embutidos"


def test_pasillo_fuera_de_alcance_deja_el_producto_fuera():
    assert categoria_de_producto("Leche entera", "/Licores/Vinos/") is None
