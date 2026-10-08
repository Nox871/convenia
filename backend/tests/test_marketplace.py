import pytest

from shared.category_filter import es_producto_de_marketplace


@pytest.mark.parametrize(
    "url",
    [
        "https://www.exito.com/mueble-de-aseo-jalisco-bla-aseo-con-colgadero-de-escobas-zf-104990319-mp/p",
        "https://www.exito.com/juego-de-dispensador-de-jabon-de-cocina-104993551-mp/p",
        "https://www.exito.com/algo-123-mp/p?skuId=1",
        "https://www.exito.com/algo-123-MP/p",
    ],
)
def test_vendedores_externos_se_detectan(url):
    assert es_producto_de_marketplace(url)


@pytest.mark.parametrize(
    "url",
    [
        "https://www.exito.com/yogurt-griego-fresa-deja-mu-120-gramo-3009647/p",
        "https://www.carulla.com/cacao-en-polvo-tosh-200-gr-3022507/p",
        "https://www.d1.com.co/espuma-de-afeitar-xen-300ml-12001738/p",
        "https://www.exito.com/jamon-mp-serrano-3011/p",   # "mp" dentro del nombre, no al final
        None,
        "",
    ],
)
def test_productos_del_supermercado_no_se_descartan(url):
    assert not es_producto_de_marketplace(url)
