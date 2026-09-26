"""Puente hacia el clasificador de categorías compartido (`shared/category_filter.py`).

`shared/` no tiene dependencias externas (sólo stdlib), así que es seguro
importarlo desde el backend aunque tenga su propio venv, separado del de
`scraper/`/`etl/`. Sirve para normalizar `source_categories.name_raw` a una
"categoría común" sin duplicar la lista de palabras clave que ya
mantiene el scraper.
"""
import sys
from functools import lru_cache
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
from shared.category_producto import categoria_por_nombre  # noqa: E402


def stems_for_label(label: str) -> list[str]:
    """Palabras clave (stems) de `ETIQUETAS_AMIGABLES` que producen esta
    etiqueta amigable, ej. "Despensa" -> ["arroz", "grano", "lenteja", ...].
    Sirve para filtrar productos por categoría a partir de la etiqueta que
    el usuario ve, sin exponerle los stems técnicos."""
    return [stem for stem, etiqueta in ETIQUETAS_AMIGABLES.items() if etiqueta == label]


@lru_cache(maxsize=4096)
def _etiqueta_por_pasillo(ruta_categoria: str | None) -> str | None:
    # Hay unos pocos cientos de pasillos distintos y miles de productos: se
    # clasifica cada pasillo una vez, no una vez por producto.
    return etiqueta_amigable(ruta_categoria)


def categoria_de_producto(nombre: str | None, ruta_categoria: str | None) -> str | None:
    """Categoría amigable de un producto. Se decide por el NOMBRE (lo que el
    producto es) y sólo si no alcanza se usa el pasillo del supermercado,
    que es inconsistente (ej. leche de coco en "Pescados y mariscos").
    Si el pasillo no pertenece al alcance de canasta familiar, el producto
    queda fuera aunque el nombre sugiera una categoría."""
    por_pasillo = _etiqueta_por_pasillo(ruta_categoria)
    if por_pasillo is None:
        return None
    return categoria_por_nombre(nombre) or por_pasillo
