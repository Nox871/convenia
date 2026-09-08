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

from shared.category_filter import etiqueta_amigable, obtener_bucket  # noqa: F401,E402
