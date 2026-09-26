from pydantic import BaseModel, Field

from app.schemas.common import PageInfo


class ProductListItem(BaseModel):
    id: str = Field(..., description="ID opaco del producto ('p-<id>' agrupado o 'sp-<id>' suelto)")
    name: str
    brand: str | None = None
    image_url: str | None = None
    # Null cuando el producto está agrupado (id 'p-'): abarca varios
    # supermercados, no tiene sentido asignarle uno solo. Poblado cuando es
    # un 'sp-' suelto (todavía sin homologar).
    supermarket_code: str | None = None
    supermarket_name: str | None = None
    price: float | None = None
    list_price: float | None = None
    currency: str | None = None
    offers_count: int = Field(
        1, description="Cuántos supermercados tienen precio para este producto"
    )
    is_matched: bool = Field(
        False, description="True si el producto ya fue homologado entre supermercados"
    )


class ProductListResponse(BaseModel):
    items: list[ProductListItem]
    pagination: PageInfo


class ProductDetail(BaseModel):
    id: str
    name: str
    brand: str | None = None
    category: str | None = None
    image_url: str | None = None
    product_url: str | None = None
    is_matched: bool
    offers_count: int
    supermarkets: list[str] = Field(
        default_factory=list, description="Códigos de los supermercados que ofrecen este producto"
    )


class ProductSuggestion(BaseModel):
    id: str = Field(..., description="ID opaco del producto ('p-<id>' o 'sp-<id>')")
    name: str
    brand: str | None = None
    score: float = Field(..., description="Qué tan parecido es el nombre al texto buscado (0-1)")
    image_url: str | None = None
    price: float | None = Field(None, description="Mejor precio disponible hoy")
    offers_count: int = Field(1, description="Supermercados que lo venden con precio disponible")


class ProductSuggestResponse(BaseModel):
    query: str
    suggestions: list[ProductSuggestion]
