import csv
import io
from datetime import datetime, timezone

from app.core.csv_export import BOM, DELIMITER, HEADERS, encode_csv, format_price, format_row


def test_precio_sin_ceros_de_mas_y_con_punto_decimal():
    assert format_price(4120.0) == "4120"
    assert format_price(3770) == "3770"
    assert format_price(1234.5) == "1234.50"
    assert format_price(None) == ""


def _fila(**extra):
    base = {
        "observed_at": datetime(2026, 9, 7, 16, 55, 41, tzinfo=timezone.utc),
        "supermarket_code": "EXITO",
        "supermarket_name": "Éxito",
        "name": "Leche FRESCAMPO entera (900 ml)",
        "brand": "FRESCAMPO",
        "price": 3770.0,
        "list_price": 4100.0,
        "currency": "COP",
        "available": True,
        "source_product_id": 12,
        "product_url": "https://www.exito.com/leche",
    }
    base.update(extra)
    return base


def test_una_fila_tiene_una_columna_por_encabezado():
    fila = format_row(_fila(), "Lácteos y huevos")

    assert len(fila) == len(HEADERS)
    assert fila[0] == "2026-09-07T16:55:41+00:00"
    assert fila[5] == "Lácteos y huevos"
    assert fila[6] == "3770"
    assert fila[9] == "si"


def test_campos_vacios_no_rompen():
    fila = format_row(_fila(brand=None, list_price=None, available=False, product_url=None), None)

    assert fila[4] == ""
    assert fila[5] == ""
    assert fila[7] == ""
    assert fila[9] == "no"


def test_un_nombre_con_el_separador_o_comillas_se_escapa_y_se_lee_de_vuelta():
    fila = format_row(_fila(name='Aceite; "premium" 900 ml'), "Despensa")
    texto = encode_csv([HEADERS, fila])

    leido = list(csv.reader(io.StringIO(texto), delimiter=DELIMITER))

    assert leido[1][3] == 'Aceite; "premium" 900 ml'
    assert len(leido[1]) == len(HEADERS)


def test_el_bom_permite_que_excel_lea_las_tildes():
    assert BOM == "﻿"
    assert "supermercado" in encode_csv([HEADERS])
