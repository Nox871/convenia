import pytest

from app.core.swap_matching import Producto, distancia_de_tamano, extraer_cantidad, puede_sustituir
from app.services import shopping_list_service as svc


def _oferta(sp_id, nombre, marca, precio, codigo, tienda):
    return {
        "source_product_id": sp_id, "name": nombre, "brand": marca, "image_url": None,
        "price": precio, "supermarket_code": codigo, "supermarket_name": tienda,
    }


def _indice(*ofertas):
    """Como `_swap_candidates`: ofertas indexadas por la primera palabra base."""
    por_palabra = {}
    for o in ofertas:
        p = Producto(nombre=o["name"], marca=o["brand"])
        if p.base:
            por_palabra.setdefault(p.base[0], []).append((o, p))
    return por_palabra


@pytest.fixture
def escenario(monkeypatch):
    """Lista de 3 ítems. Jumbo tiene 2 tal cual y le falta la cebolla en polvo, pero
    vende otra cebolla en polvo. Éxito sólo tiene 1 y no tiene reemplazo para el resto."""
    items = [
        {"id": 1, "name": "Arroz DONA PEPA parbolizado (1000 gr)", "brand": "Doña Pepa", "quantity": 1},
        {"id": 2, "name": "Pollo Azteca Desmechado Salsa 300g", "brand": "Azteca", "quantity": 2},
        {"id": 3, "name": "Cebolla polvo Mccormick x74g", "brand": "Mccormick", "quantity": 1},
    ]
    filas = []

    def fila(item_id, codigo, nombre, precio):
        filas.append({"item_id": item_id, "quantity": next(i["quantity"] for i in items if i["id"] == item_id),
                      "supermarket_id": 1 if codigo == "JUMBO" else 2, "supermarket_code": codigo,
                      "supermarket_name": nombre, "price": precio})

    fila(1, "JUMBO", "Jumbo", 9000); fila(2, "JUMBO", "Jumbo", 7000); fila(3, "JUMBO", "Jumbo", None)
    fila(1, "EXITO", "Éxito", 8500); fila(2, "EXITO", "Éxito", None); fila(3, "EXITO", "Éxito", None)

    candidatos = _indice(
        _oferta(101, "Cebolla en polvo Badia 70 gr", "Badia", 4200, "JUMBO", "Jumbo"),
        _oferta(102, "Cebolla en polvo Badia 70 gr", "Badia", 3900, "EXITO", "Éxito"),
        _oferta(103, "Cebolla cabezona 1 kg", "Sm", 3000, "JUMBO", "Jumbo"),  # otro tipo: no sirve
    )
    monkeypatch.setattr(svc, "_ensure_list_owned", lambda *a, **k: None)
    monkeypatch.setattr(svc.shopping_list_repository, "get_items", lambda conn, list_id: items)
    monkeypatch.setattr(svc.shopping_list_repository, "get_cost_breakdown_rows", lambda *a, **k: filas)
    monkeypatch.setattr(svc, "_swap_candidates", lambda conn, codes: candidatos)
    return items


def test_la_tienda_con_reemplazos_para_todo_es_completable_y_va_primero(escenario):
    r = svc.get_single_store_options(None, 1, "x")
    jumbo, exito = r.options[0], r.options[1]
    assert jumbo.supermarket_code == "JUMBO" and jumbo.completable
    assert jumbo.items_priced == 2
    assert [x.item_id for x in jumbo.replacements] == [3]
    assert jumbo.replacements[0].substitute.name == "Cebolla en polvo Badia 70 gr"
    # 9.000 + 2 x 7.000 + 4.200 = lista completa en Jumbo
    assert jumbo.current_total == 23000
    assert jumbo.total_if_replaced == 27200


def test_si_a_algo_no_se_le_encuentra_reemplazo_no_es_completable(escenario):
    r = svc.get_single_store_options(None, 1, "x")
    exito = next(o for o in r.options if o.supermarket_code == "EXITO")
    assert not exito.completable
    assert exito.total_if_replaced is None
    sin_reemplazo = [x.item_name for x in exito.replacements if x.substitute is None]
    assert any("Pollo" in n for n in sin_reemplazo)  # no hay otro pollo desmechado: no se inventa
    assert r.options.index(exito) == 1  # las no completables van después


def test_el_reemplazo_es_del_mismo_tipo_no_de_otra_cosa(escenario):
    r = svc.get_single_store_options(None, 1, "x")
    jumbo = r.options[0]
    assert "cabezona" not in jumbo.replacements[0].substitute.name


def test_una_tienda_sin_nada_de_la_lista_no_aparece(monkeypatch, escenario):
    filas = [{"item_id": 1, "quantity": 1, "supermarket_id": 9, "supermarket_code": "D1",
              "supermarket_name": "D1", "price": None}]
    monkeypatch.setattr(svc.shopping_list_repository, "get_cost_breakdown_rows", lambda *a, **k: filas)
    assert svc.get_single_store_options(None, 1, "x").options == []


def test_lista_vacia(monkeypatch):
    monkeypatch.setattr(svc, "_ensure_list_owned", lambda *a, **k: None)
    monkeypatch.setattr(svc.shopping_list_repository, "get_items", lambda conn, list_id: [])
    monkeypatch.setattr(svc.shopping_list_repository, "get_cost_breakdown_rows", lambda *a, **k: [])
    assert svc.get_single_store_options(None, 1, "x").options == []


def test_tolerancia_de_tamano_para_completar_es_mayor_que_la_de_ahorrar():
    original = Producto("Cebolla en polvo Mccormick 74 g", "Mccormick")
    otro = Producto("Cebolla en polvo Badia 100 g", "Badia")  # +35 %
    assert not puede_sustituir(original, otro)            # para "ahorrar": 10 %
    assert puede_sustituir(original, otro, tolerancia=0.35)
    muy_distinto = Producto("Cebolla en polvo Badia 500 g", "Badia")
    assert not puede_sustituir(original, muy_distinto, tolerancia=0.35)


def test_distancia_de_tamano():
    a, b = extraer_cantidad("x 100 g"), extraer_cantidad("x 50 g")
    assert distancia_de_tamano(a, b) == 0.5
    assert distancia_de_tamano(a, a) == 0
    assert distancia_de_tamano(a, extraer_cantidad("x 1 l")) == 1.0
    assert distancia_de_tamano(None, None) == 0


def test_siempre_busca_otro_del_mismo_tipo_aunque_cambie_marca_y_tamano():
    from app.services.shopping_list_service import _mejor_sustituto

    item = {"name": "Pollo Azteca Desmechado Salsa 300g", "brand": "Azteca"}
    candidatos = _indice(
        _oferta(1, "Pechuga de pollo Pimpollo 500 g", "Pimpollo", 12000, "EXITO", "Éxito"),
        _oferta(2, "Pollo entero Granja 1 kg", "Granja", 21000, "EXITO", "Éxito"),
        _oferta(3, "Arroz Diana 500 g", "Diana", 3000, "EXITO", "Éxito"),
    )
    # no hay el mismo pollo: se elige el más cercano al precio que la persona ya pagaba
    elegido = _mejor_sustituto(item, "EXITO", candidatos, precio_referencia=11000)
    assert elegido["source_product_id"] == 1
    premium = _mejor_sustituto(item, "EXITO", candidatos, precio_referencia=22000)
    assert premium["source_product_id"] == 2


def test_papas_de_otro_tipo_reemplazan_papas_futboleras():
    from app.services.shopping_list_service import _mejor_sustituto

    item = {"name": "Papas Edición Futbolera Kythos 200 G", "brand": "Kythos"}
    candidatos = _indice(_oferta(7, "Papas fritas Margarita pollo 105 g", "Margarita", 3500, "EXITO", "Éxito"))
    assert _mejor_sustituto(item, "EXITO", candidatos, 5000)["source_product_id"] == 7


def test_otro_tipo_distinto_no_se_inventa():
    from app.services.shopping_list_service import _mejor_sustituto

    item = {"name": "Pollo Azteca Desmechado Salsa 300g", "brand": "Azteca"}
    candidatos = _indice(_oferta(3, "Arroz Diana 500 g", "Diana", 3000, "EXITO", "Éxito"))
    assert _mejor_sustituto(item, "EXITO", candidatos, 5000) is None
