from pathlib import Path

from etl.core import SupermarketETL


def _p(i, nombre, marca, categoria, precio):
    return {"product_id": str(i), "product_name": nombre, "brand": marca,
            "category": categoria, "price": precio}


def _filtrar(productos):
    return SupermarketETL("OLIMPICA", Path(".") )._filtrar_productos(productos)


def test_variantes_iguales_se_unen_y_queda_la_mas_barata():
    out = _filtrar([
        _p(1, "Bebida Speed Max 250 ml", "Speed", "/Mercado/Bebidas/", 1750),
        _p(2, "Bebida Speed Max 250 ml", "Speed", "/Mercado/Bebidas/", 1400),
    ])
    assert [p["product_id"] for p in out] == ["2"]


def test_fuera_de_canasta_y_aparatos_no_entran():
    out = _filtrar([
        _p(1, "Televisor 55", "LG", "/Tecnologia/TV/", 2000000),
        _p(2, "Mueble de aseo Lirio", "x", "/Mercado/Aseo del hogar/", 50000),
        _p(3, "Disfraz de Goku", "x", "/Especiales/Halloween/Disfraces Adultos/", 90000),
        _p(4, "Leche entera", "Alpina", "/Supermercado/", 3000),
    ])
    assert [p["product_id"] for p in out] == ["4"]


def test_productos_sin_precio_pasan_al_etl_para_marcarse_no_disponibles():
    out = _filtrar([
        _p(1, "Cafe Arriero", "Arriero", "/Mercado/Despensa/", 9000),
        _p(2, "Cafe Arriero molido", "Arriero", "/Mercado/Despensa/", 0),
        _p(3, "Cafe Arriero tostado", "Arriero", "/Mercado/Despensa/", None),
    ])
    assert {p["product_id"] for p in out} == {"1", "2", "3"}


def test_mismo_codigo_de_barras_en_la_misma_tienda_se_une_al_mas_barato():
    ean = "7702137302073"
    out = _filtrar([
        {**_p(1, "Malla Esponja Bon Bril X2", "Bon Bril", "/Mercado/Aseo del hogar/", 900), "ean": ean},
        {**_p(2, "Esponja multiusos doble malla", "Bon Bril", "/Mercado/Aseo del hogar/", 1200), "ean": ean},
        {**_p(3, "Otra esponja distinta", "Bon Bril", "/Mercado/Aseo del hogar/", 500), "ean": "7702213411569"},
    ])
    assert sorted(p["product_id"] for p in out) == ["1", "3"]


def test_ean_invalido_no_une_productos():
    out = _filtrar([
        {**_p(1, "Producto A", "x", "/Mercado/Despensa/", 900), "ean": "2000000012345"},
        {**_p(2, "Producto B", "x", "/Mercado/Despensa/", 1200), "ean": "2000000012345"},
    ])
    assert len(out) == 2
