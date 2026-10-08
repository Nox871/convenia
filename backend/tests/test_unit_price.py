from app.schemas.price import PriceOffer
from app.services.product_service import _with_unit_price


def _offer(price):
    return PriceOffer(supermarket_code="EXITO", supermarket_name="Éxito", price=price)


def test_cafe_instantaneo_de_50_g_se_muestra_por_100_g():
    o = _with_unit_price(_offer(12000), 50, "g")
    assert o.unit_label == "$/100 g"
    assert o.unit_price == 24000


def test_arroz_se_sigue_mostrando_por_kg():
    o = _with_unit_price(_offer(2793), 460, "g")
    assert o.unit_label == "$/kg"
    assert round(o.unit_price) == 6072


def test_liquido_caro_se_muestra_por_100_ml():
    o = _with_unit_price(_offer(30000), 100, "ml")
    assert o.unit_label == "$/100 ml"
    assert o.unit_price == 30000


def test_unidades_no_cambian():
    o = _with_unit_price(_offer(900), 2, "un")
    assert o.unit_label == "$/unidad"
