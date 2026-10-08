"""Una página que falla en VTEX NO es el final de la categoría (Jumbo, Éxito, Carulla, Olímpica)."""
import asyncio
import importlib
import sys
from pathlib import Path

import pytest

pytest.importorskip("crawl4ai")  # sólo corre con el entorno del scraper

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scraper"))

TIENDAS = ["jumbo", "exito", "carulla", "olimpica"]


def _correr(monkeypatch, tienda, respuestas):
    """respuestas: lista por página; una lista de ids, [] (fin) o None (falló)."""
    mod = importlib.import_module(f"connectors.{tienda}.scraper")
    pedidas = []

    async def falso_vtex(client, url, pagina):
        pedidas.append(pagina)
        return respuestas[pagina - 1] if pagina <= len(respuestas) else []

    async def sin_pdp(*args, **kwargs):
        return None

    monkeypatch.setattr(mod, "consultar_vtex", falso_vtex)
    if hasattr(mod, "enriquecer_producto_con_pagina"):
        monkeypatch.setattr(mod, "enriquecer_producto_con_pagina", sin_pdp)
    monkeypatch.setattr(
        mod, "construir_producto",
        lambda p, url, pagina, ts: {"product_id": p, "product_name": f"Arroz {p}", "price": 1000},
    )
    monkeypatch.setattr(mod, "DELAY_ENTRE_PETICIONES", 0)
    mod.CATEGORIAS_INCOMPLETAS.clear()
    productos = asyncio.run(
        mod.procesar_categoria(None, None, f"https://www.{tienda}.com/mercado/despensa", 1, 1)
    )
    return mod, productos, pedidas


def _ids(desde, n):
    return list(range(desde + 1, desde + n + 1))


@pytest.mark.parametrize("tienda", TIENDAS)
def test_pagina_fallida_se_salta_y_se_sigue(monkeypatch, tienda):
    mod, productos, pedidas = _correr(monkeypatch, tienda, [_ids(0, 50), None, _ids(100, 50), _ids(200, 10)])
    assert pedidas == [1, 2, 3, 4]
    assert len(productos) == 110  # páginas 1, 3 y 4
    assert len(mod.CATEGORIAS_INCOMPLETAS) == 1  # y queda marcada como incompleta


@pytest.mark.parametrize("tienda", TIENDAS)
def test_tres_fallos_seguidos_cierran_la_categoria(monkeypatch, tienda):
    mod, productos, pedidas = _correr(monkeypatch, tienda, [_ids(0, 50), None, None, None, _ids(500, 50)])
    assert pedidas == [1, 2, 3, 4]
    assert len(productos) == 50
    assert mod.CATEGORIAS_INCOMPLETAS


@pytest.mark.parametrize("tienda", TIENDAS)
def test_categoria_normal_no_se_marca_incompleta(monkeypatch, tienda):
    mod, productos, _ = _correr(monkeypatch, tienda, [_ids(0, 50), _ids(50, 12)])
    assert len(productos) == 62
    assert not mod.CATEGORIAS_INCOMPLETAS
