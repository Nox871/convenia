"""Compatibilidad hacia atrás.

La implementación real de este clasificador vive en `shared/category_filter.py`
(sin dependencias externas, importable también desde `backend/`, que tiene su
propio venv separado del de `scraper/`). Este módulo sólo re-exporta esos
nombres para no romper los imports existentes:

    from core.category_filter import clasificar_categoria, factor_paginas
"""
import sys
from pathlib import Path

_PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from shared.category_filter import (  # noqa: F401,E402
    es_producto_de_marketplace,
    es_producto_no_canasta,
    ETIQUETAS_AMIGABLES,
    FACTOR_PAGINAS_ALTA_DENSIDAD,
    PALABRAS_ALTA_DENSIDAD,
    PALABRAS_EXCLUSION,
    PALABRAS_INCLUSION,
    clasificar_categoria,
    es_categoria_relevante,
    etiqueta_amigable,
    factor_paginas,
    normalizar_texto,
    obtener_bucket,
)
