from app.core.basket import CANTIDAD_MAXIMA, Candidato, armar, elegir


def _c(i, precio, tiendas=2):
    return Candidato(id=f"p-{i}", name=f"Producto {i}", price=precio, offers_count=tiendas)


def _cands(*precios):
    return [_c(i, p) for i, p in enumerate(precios, 1)]


def test_elegir_por_nivel_usa_el_ranking_de_precios():
    c = _cands(1000, 2000, 3000, 4000, 5000)
    assert elegir(c, "economico").price == 1000
    assert elegir(c, "medio").price == 3000
    # "alto" es el percentil 85, no el más caro: el último suele ser un caso extremo
    assert elegir(c, "alto").price == 4000


def test_elegir_ignora_sin_precio_y_prefiere_los_conocidos():
    sueltos = [_c(1, 100, tiendas=1), _c(2, 9000, tiendas=1)]
    conocidos = _cands(2000, 3000, 4000)
    assert elegir(sueltos + conocidos, "economico").price == 2000  # el de $100 es una marca suelta
    assert elegir([Candidato("p-9", "x", 0)], "medio") is None
    assert elegir([], "medio") is None


def test_sin_presupuesto_una_unidad_de_cada_uno_en_el_nivel_pedido():
    c = armar([("arroz", _cands(1000, 2000, 3000)), ("leche", _cands(2000, 3000, 4000))], nivel="medio")
    assert c.nivel_usado == "medio"
    assert [l.cantidad for l in c.lineas] == [1, 1]
    assert c.total == 2000 + 3000


def test_con_presupuesto_justo_se_mejora_de_nivel_hasta_donde_alcanza():
    terminos = [("a", _cands(1000, 2000, 3000)), ("b", _cands(1000, 2000, 3000))]
    c = armar(terminos, nivel="alto", presupuesto=4000)
    assert c.total <= 4000
    assert c.nivel_usado == "medio"      # los dos subieron un escalón: 2000 + 2000
    assert c.sin_presupuesto_para == []


def test_la_prioridad_mejora_primero_y_el_resultado_puede_ser_mixto():
    terminos = [("a", _cands(1000, 2000, 3000)), ("b", _cands(1000, 2000, 3000))]
    c = armar(terminos, nivel="alto", presupuesto=3000)
    assert [l.candidato.price for l in c.lineas] == [2000, 1000]
    assert c.nivel_usado == "mixto"


def test_con_presupuesto_amplio_se_llega_al_nivel_pedido():
    terminos = [("a", _cands(1000, 2000, 3000, 4000, 5000)), ("b", _cands(1000, 2000, 3000, 4000, 5000))]
    c = armar(terminos, nivel="alto", presupuesto=1_000_000)
    assert c.nivel_usado == "alto"
    assert all(l.candidato.price == 4000 for l in c.lineas)


def test_si_ni_el_economico_cabe_se_quitan_los_de_menor_prioridad():
    terminos = [("pan", _cands(3000, 4000, 5000)), ("huevos", _cands(3000, 4000, 5000)),
                ("leche", _cands(3000, 4000, 5000)), ("cereal", _cands(3000, 4000, 5000))]
    c = armar(terminos, nivel="medio", presupuesto=7000)
    nombres = [l.termino for l in c.lineas]
    assert nombres == ["pan", "huevos"]
    assert c.sin_presupuesto_para == ["cereal", "leche"]
    assert c.total <= 7000
    assert not c.excede_presupuesto


def test_si_sobra_dinero_se_suben_cantidades_por_prioridad_sin_pasarse():
    c = armar([("arroz", _cands(2000, 2000, 2000)), ("leche", _cands(3000, 3000, 3000))],
              nivel="medio", presupuesto=17000)
    assert c.total <= 17000
    assert c.lineas[0].cantidad >= c.lineas[1].cantidad  # lo prioritario recibe primero
    assert max(l.cantidad for l in c.lineas) <= CANTIDAD_MAXIMA


def test_el_total_nunca_supera_el_presupuesto():
    for presupuesto in (3000, 8000, 15000, 40000, 100000):
        c = armar([("a", _cands(1000, 1500, 2500)), ("b", _cands(2000, 3000, 4500)),
                   ("c", _cands(500, 900, 1500))], nivel="alto", presupuesto=presupuesto)
        assert c.total <= presupuesto or c.excede_presupuesto


def test_presupuesto_menor_que_el_primer_producto_avisa_que_excede():
    c = armar([("pan", _cands(5000, 6000, 7000)), ("leche", _cands(3000, 4000, 5000))],
              nivel="medio", presupuesto=1000)
    assert c.excede_presupuesto
    assert [l.termino for l in c.lineas] == ["pan"]


def test_termino_sin_resultados_queda_como_no_encontrado():
    c = armar([("arroz", _cands(1000, 2000, 3000)), ("xyz", [])], nivel="medio")
    assert c.lineas[1].candidato is None
    assert c.total == 2000


def test_nivel_desconocido_cae_a_medio():
    c = armar([("a", _cands(1000, 2000, 3000))], nivel="lujo")
    assert c.nivel_pedido == "medio"
