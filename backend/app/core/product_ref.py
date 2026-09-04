"""ID opaco de producto expuesto por la API.

Mientras `products`/`product_matches` estén vacías, cada producto listado
proviene directamente de `source_products` (un registro por supermercado).
Cuando exista homologación, un mismo producto canónico agrupará varios
`source_products`. Para que la API no tenga que cambiar de forma cuando eso
ocurra, el "id" que ve el cliente nunca es un `source_products.id` ni un
`products.id` desnudo — es un identificador con prefijo que dice de qué tabla
proviene:

    "sp-123"  -> source_products.id = 123 (producto de UN supermercado, sin homologar)
    "p-45"    -> products.id = 45          (producto canónico, ya homologado)

Esto evita confundir external_id / source_products.id / products.id, y deja
que la capa de repositorio decida, id por id, de qué tabla leer.
"""
from dataclasses import dataclass
from typing import Literal

ProductKind = Literal["source", "canonical"]

_SOURCE_PREFIX = "sp-"
_CANONICAL_PREFIX = "p-"


@dataclass(frozen=True)
class ProductRef:
    kind: ProductKind
    numeric_id: int

    def encode(self) -> str:
        prefix = _SOURCE_PREFIX if self.kind == "source" else _CANONICAL_PREFIX
        return f"{prefix}{self.numeric_id}"


def encode_source_ref(source_product_id: int) -> str:
    return ProductRef(kind="source", numeric_id=source_product_id).encode()


def encode_canonical_ref(product_id: int) -> str:
    return ProductRef(kind="canonical", numeric_id=product_id).encode()


def parse_product_ref(raw: str) -> ProductRef:
    if raw.startswith(_SOURCE_PREFIX):
        kind: ProductKind = "source"
        numeric_part = raw[len(_SOURCE_PREFIX):]
    elif raw.startswith(_CANONICAL_PREFIX):
        kind = "canonical"
        numeric_part = raw[len(_CANONICAL_PREFIX):]
    else:
        raise ValueError(
            f"ID de producto inválido: {raw!r}. Debe tener el formato 'sp-<id>' o 'p-<id>'."
        )

    if not numeric_part.isdigit():
        raise ValueError(f"ID de producto inválido: {raw!r}")

    return ProductRef(kind=kind, numeric_id=int(numeric_part))
