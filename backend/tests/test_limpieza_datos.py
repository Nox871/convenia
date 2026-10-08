import pytest

from app.core.spelling import corregir_palabra, distancia, sugerir_busqueda
from shared.brand import limpiar_marca
from shared.category_filter import es_producto_no_canasta


@pytest.mark.parametrize("sucia", [
    "![](https://d1tienda.com/imagenes/antibacterial.png)",
    "![ARROZ-BLANCO-PREMIUM-ALBAR](https://cdn.x.com/a.jpg)",
    "https://www.d1.com.co/marca",
    "logo-marca.png",
    "",
    None,
    "   ",
    "x" * 80,
    "Sin marca",
    "SIN MARCA",
    "N/A",
])
def test_marcas_que_son_basura_se_descartan(sucia):
    assert limpiar_marca(sucia) is None


@pytest.mark.parametrize("marca", ["Diana", "BON BRIL", "Doña Gallina", "  Alpina  "])
def test_marcas_normales_se_conservan(marca):
    assert limpiar_marca(marca) == " ".join(marca.split())


@pytest.mark.parametrize("nombre,marca", [
    ("Bombillo LED 12 W Luz Blanca Futura 1 Und", "FUTURA"),
    ("Bateria Alcalina Aa Futura 4 Und", "FUTURA"),
    ("Sombrilla Automatica Uv Red Flag", "RED FLAG"),
    ("Organizador Con Compartimentos Red Flag X1 U", None),
    ("Carrito de Mercado D1", "D1"),
    ("Bolsa de Papel D1", "D1"),
    ("Bolsa Roja Reutilizable 40X42 Cm D1", "D1"),
    ("Bolsas Reutilizable Tidy House 5 Unds", "TIDY HOUSE"),
    ("Encendedor Tokai", "TOKAI"),
    ("Rallador Cónico con Mango de Madera", "RED FLAG"),
    ("Bolsa de Lavanderia Red Flag X 1 Ud", "RED FLAG"),
])
def test_articulos_de_hogar_no_son_canasta(nombre, marca):
    assert es_producto_no_canasta(nombre, marca)


@pytest.mark.parametrize("nombre,marca", [
    ("Detergente Líquido Bonaropa Baby 1000 Ml", "BONAROPA"),
    ("Esponja Multiusos Tidy House 3 Und", "TIDY HOUSE"),
    ("Bolsa de basura negra 10 und", "x"),
    ("Pilas de cacao en polvo", "x"),
    ("Jabón en Barra Brilla King 300 Gr", "BRILLA KING"),
    ("Café Nescafé tradición 50 gr", "Nescafe"),
])
def test_aseo_y_comida_legitimos_se_conservan(nombre, marca):
    assert not es_producto_no_canasta(nombre, marca)


@pytest.mark.parametrize("escrito,esperado", [("caef", "cafe"), ("arorz", "arroz"), ("lceh", "lech")])
def test_letras_cambiadas_de_lugar_cuentan_como_un_error(escrito, esperado):
    vocab = {"cafe": 400, "arroz": 900, "leche": 700}
    if esperado == "lech":
        # "lceh" -> "leche" necesita 2 ediciones: no se corrige (no se inventa)
        assert corregir_palabra(escrito, vocab) is None
    else:
        assert corregir_palabra(escrito, vocab) == esperado


def test_distancia_con_transposicion():
    assert distancia("caef", "cafe", 1) == 1
    assert distancia("arorz", "arroz", 1) == 1
    assert distancia("gato", "perro", 2) > 2


def test_frase_con_letras_cambiadas():
    vocab = {"cafe": 400, "arroz": 900, "diana": 60}
    assert sugerir_busqueda("arorz diana", vocab) == "arroz diana"
    assert sugerir_busqueda("caef", vocab) == "cafe"
