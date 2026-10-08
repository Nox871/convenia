import pytest

from shared.category_filter import es_producto_no_canasta


@pytest.mark.parametrize(
    "nombre",
    [
        "Mueble De Aseo Lirio, Blanco, Con Cinco Entrepaños Zf",
        "Juego De Dispensador De Jabon De Cocina",
        "Aspiradora Inalámbrica Shark Vacmop Para Pisos Duros",
        "Mini Batidor Eléctrico Portátil Mezclador De Mano",
        "Trapeadora A Vapor De Pisos Duros Shark",
        "Set X2 Dispensador Espuma",
    ],
)
def test_muebles_y_aparatos_se_descartan(nombre):
    assert es_producto_no_canasta(nombre)


@pytest.mark.parametrize(
    "nombre",
    [
        "Café Arriero 2 Unidades Entrega 1 Hora",
        "Huevo Tsidkenu Rojo Premium Aa X 20",
        "2 Paquetes De Chorizos Santa Rosano X 330 Gr",
        "Limpiador De Muebles En Aerosol",
        "Jabón Líquido Con Dispensador 500 Ml",
        "Escoba Giratoria G6",
        "Abrillantador Piso Laminado Fuller",
        None,
        "",
    ],
)
def test_canasta_y_aseo_se_conservan(nombre):
    assert not es_producto_no_canasta(nombre)


from shared.category_producto import categoria_de_producto  # noqa: E402


@pytest.mark.parametrize(
    "nombre,ruta",
    [
        ("Leche Parmalat Entera x1100ml", "/Supermercado/"),
        ("Arroz Diana blanco 500g", ""),
    ],
)
def test_pasillo_generico_se_decide_por_el_nombre(nombre, ruta):
    assert categoria_de_producto(nombre, ruta) is not None


@pytest.mark.parametrize(
    "nombre,ruta",
    [
        ("Set 36 Esferas Navideñas", "/Especiales/Navidad/Decoración Navideña/"),
        ("Disfraz de Goku", "/Especiales/Halloween/Disfraces Adultos/"),
        ("Televisor Samsung 55 pulgadas", "/Supermercado/"),
        ("Televisor Samsung 55 pulgadas", "/Tecnología/Televisores/"),
        ("Alimento húmedo Whiskas gato", "/Mascotas/Gatos/Alimento Húmedo/"),
    ],
)
def test_lo_que_no_es_canasta_queda_fuera(nombre, ruta):
    assert categoria_de_producto(nombre, ruta) is None
