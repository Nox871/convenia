from pydantic import BaseModel, Field, field_validator

from shared.brand import limpiar_marca

from app.schemas.common import PageInfo


class StoreOffer(BaseModel):
    supermarket_code: str
    supermarket_name: str
    price: float


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
    offers: list[StoreOffer] = Field(
        default_factory=list,
        description="Precio en cada supermercado al alcance, del más barato al más caro",
    )

    @field_validator("brand", mode="before")
    @classmethod
    def _marca_limpia(cls, v):
        return limpiar_marca(v)



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

    @field_validator("brand", mode="before")
    @classmethod
    def _marca_limpia(cls, v):
        return limpiar_marca(v)



class ProductSuggestion(BaseModel):
    id: str = Field(..., description="ID opaco del producto ('p-<id>' o 'sp-<id>')")
    name: str
    brand: str | None = None
    score: float = Field(..., description="Qué tan parecido es el nombre al texto buscado (0-1)")
    image_url: str | None = None
    price: float | None = Field(None, description="Mejor precio disponible hoy")
    offers_count: int = Field(1, description="Supermercados que lo venden con precio disponible")

    @field_validator("brand", mode="before")
    @classmethod
    def _marca_limpia(cls, v):
        return limpiar_marca(v)



class ProductSuggestResponse(BaseModel):
    query: str
    suggestions: list[ProductSuggestion]


class DidYouMeanResponse(BaseModel):
    query: str
    suggestion: str | None = Field(
        None, description="Búsqueda corregida ('arroz' para 'aroz'), o null si no hay nada que corregir"
    )


class BasketLine(BaseModel):
    term: str = Field(..., description="Lo que se pidió, ej. 'huevos'")
    found: bool = Field(..., description="False si no hay ningún producto con precio para ese término")
    product: ProductListItem | None = None
    quantity: int = 1
    subtotal: float = 0


class BasketResponse(BaseModel):
    tier_requested: str
    tier_used: str = Field(..., description="Nivel con el que realmente se armó (baja si el presupuesto no alcanzaba)")
    budget: float | None = None
    total: float
    remaining: float | None = Field(None, description="Presupuesto que sobra, si se indicó uno")
    exceeds_budget: bool = Field(False, description="True si ni el primer producto cabe en el presupuesto")
    dropped_terms: list[str] = Field(default_factory=list, description="Términos que no cupieron en el presupuesto")
    items: list[BasketLine]


class PopularSearch(BaseModel):
    term: str
    searches: int


class PopularSearchesResponse(BaseModel):
    items: list[PopularSearch]
