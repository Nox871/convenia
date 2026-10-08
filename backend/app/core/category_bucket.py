"""Puente hacia el clasificador de categorías compartido (`shared/category_filter.py`).

`shared/` no tiene dependencias externas (sólo stdlib), así que es seguro
importarlo desde el backend aunque tenga su propio venv, separado del de
`scraper/`/`etl/`. Sirve para normalizar `source_categories.name_raw` a una
"categoría común" sin duplicar la lista de palabras clave que ya
mantiene el scraper.
"""
import sys
from pathlib import Path

_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from shared.category_filter import (  # noqa: F401,E402
    ETIQUETAS_AMIGABLES,
    etiqueta_amigable,
    normalizar_texto,
    obtener_bucket,
)
# `categoria_de_producto` vive en shared/ (no aquí) para que `etl/homologacion`
# pueda usar la MISMA regla para agrupar candidatos a homologar -- ver su
# docstring en shared/category_producto.py.
from shared.category_producto import categoria_de_producto, categoria_por_nombre  # noqa: F401,E402


def stems_for_label(label: str) -> list[str]:
    """Palabras clave (stems) de `ETIQUETAS_AMIGABLES` que producen esta
    etiqueta amigable, ej. "Despensa" -> ["arroz", "grano", "lenteja", ...].
    Sirve para filtrar productos por categoría a partir de la etiqueta que
    el usuario ve, sin exponerle los stems técnicos."""
    return [stem for stem, etiqueta in ETIQUETAS_AMIGABLES.items() if etiqueta == label]
