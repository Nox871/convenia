from app.core.category_bucket import etiqueta_amigable, stems_for_label


def test_stems_for_label_devuelve_las_palabras_de_esa_etiqueta():
    stems = stems_for_label("Lácteos y huevos")
    assert "lacte" in stems and "huevo" in stems
    assert "arroz" not in stems


def test_stems_for_label_desconocida_devuelve_lista_vacia():
    assert stems_for_label("Etiqueta que no existe") == []


def test_etiqueta_amigable_traduce_una_ruta_tecnica():
    assert etiqueta_amigable("/Despensa/Granos/Arroz/") == "Despensa"


def test_etiqueta_amigable_no_expone_categorias_fuera_de_alcance():
    assert etiqueta_amigable("/Tecnologia/Televisores/") is None
