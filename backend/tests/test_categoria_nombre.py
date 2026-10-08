import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import pytest

from shared.category_producto import BEBIDAS, CARNES, FRUTAS, SNACKS, categoria_por_nombre

CASOS = [
    ("MANZANA FRIOPACK BJA *24 POSTOBON 1 und", BEBIDAS),
    ("Refresco en polvo FRUTINO sabor a maracuyá", "Despensa"),
    ("Mezcla FRUTINO Polvo Bebida Salpicon Frutos Amarillos", "Despensa"),
    ("Bon Bon Bum Fresa Unidad 19 G", SNACKS),
    ("Caramelos HALLS extra fuerte mentol eucalipto", SNACKS),
    ("Bolitas de chocolate Chokis", SNACKS),
    ("Boliqueso CHEETOS horneados (34 gr)", SNACKS),
    ("Chocolatina GOL oscura rellena (31 gr)", SNACKS),
    ("Frutos secos LA ESPECIAL nueces, almendra", SNACKS),
    ("Mejillones Jugosos ANTILLANA 500 gr", CARNES),
    ("Manzana Roja 1 und", FRUTAS),
    ("Durazno 1 und", FRUTAS),
]


@pytest.mark.parametrize("nombre,esperada", CASOS)
def test_categoria_por_nombre(nombre, esperada):
    assert categoria_por_nombre(nombre) == esperada


def test_fruta_normal_no_se_confunde_con_gaseosa():
    assert categoria_por_nombre("Manzana verde kg") == FRUTAS


@pytest.mark.parametrize("nombre", ["Ajo TRICONDOR condimento (55 gr)", "Ajo molido Doña Gallina 100 g", "Ajo en polvo Badia"])
def test_ajo_condimento_es_despensa(nombre):
    from shared.category_producto import DESPENSA
    assert categoria_por_nombre(nombre) == DESPENSA


def test_ajo_fresco_sigue_en_frutas():
    assert categoria_por_nombre("Ajo cabeza 1 und") == FRUTAS
    assert categoria_por_nombre("Ajo 100 g") == FRUTAS


@pytest.mark.parametrize("nombre,esperada", [
    ("Refresco en polvo FRUTINO sabor a maracuyá (10 gr)", "Despensa"),
    ("Mezcla FRUTINO Polvo Bebida Salpicon", "Despensa"),
    ("Bebida refrescante CLIGHT sin calorías sabor mandarina (14 gr)", "Despensa"),
    ("Jugo CARULLA Limon (500 ml)", "Bebidas"),
    ("Galletas OREO original (54 gr)", "Snacks"),
    ("Cebolla pura El Rey bolsa x25g", "Despensa"),
    ("Ajo TRICONDOR condimento (55 gr)", "Despensa"),
    ("Mini Chicles Besties 12 Gr", "Snacks"),
    ("Mini chuzos FRIKO HF marinados x6und", "Carnes y embutidos"),
    ("Mini Viennoiseria Cuisine & Co x330gr", "Panadería y desayuno"),
    ("Cebolla cabezona blanca kg", "Frutas y verduras"),
])
def test_casos_reportados_por_el_usuario(nombre, esperada):
    assert categoria_por_nombre(nombre) == esperada


@pytest.mark.parametrize("nombre,esperada", [
    ("Bolsa ARROZ SONORA PREMIUM blanco (2500 gr)", "Despensa"),
    ("Chicharrón Bayter Limón 100g", "Snacks"),
    ("Barra de cereal ALCAGUETE moccachino (150 gr)", "Snacks"),
    ("BEB SILK ALMENDRA VAINILL/ENDULZAR 946ML", "Bebidas"),
    ("BEB HIDRAT GATORLIT COCO 620ML", "Bebidas"),
    ("Mr. Musculo Limpiador para Inodoro", "Aseo y cuidado personal"),
    ("Alimento Toning Almendra Original en Polvo 400 G", "Despensa"),
    ("Alimento lácteo COLANTA yagur paquete surtido", "Lácteos y huevos"),
    ("Papas Cuisine & Co Congeladas Pre Fritas x1000grs", "Congelados"),
    ("Papas Margarita naturales (300 gr)", "Snacks"),
    ("Crema coco MEDALLA DE ORO 400 ML", "Despensa"),
    ("Sazonador DON SABOR polvo (60 gr)", "Despensa"),
    ("Torta María Luisa x12 Porciones", "Panadería y desayuno"),
    ("Zumo de Coco 250 Ml", "Bebidas"),
    ("Res Carne Para Asar 500 G", "Carnes y embutidos"),
])
def test_casos_de_la_auditoria(nombre, esperada):
    assert categoria_por_nombre(nombre) == esperada


def test_condimento_granaroma_y_aji_fresco():
    assert categoria_por_nombre("Ají molido Granaroma x16gr") == "Despensa"
