from datetime import datetime

from pydantic import BaseModel, Field, model_validator


class ShoppingListCreate(BaseModel):
    owner_ref: str = Field(..., description="Identificador de dispositivo de quien crea la lista")
    name: str


class ShoppingListRename(BaseModel):
    name: str


class ShoppingListClaim(BaseModel):
    owner_ref: str = Field(..., description="Identificador del dispositivo cuyas listas pasan a la cuenta")


class ShoppingListClaimResponse(BaseModel):
    claimed: int


class ShoppingListBudget(BaseModel):
    budget: int | None = Field(
        None, ge=0, le=1_000_000_000,
        description="Presupuesto en pesos; null lo quita",
    )


class ShoppingListItemCreate(BaseModel):
    product_id: str | None = Field(
        None, description="ID opaco 'p-<id>' o 'sp-<id>' del producto a agregar"
    )
    quantity: int = Field(1, ge=1)

    @model_validator(mode="after")
    def _require_product_id(self):
        if not self.product_id:
            raise ValueError("'product_id' es requerido")
        return self


class ShoppingListItemUpdate(BaseModel):
    quantity: int = Field(..., ge=1)


class ShoppingListItem(BaseModel):
    id: int
    product_id: str = Field(..., description="ID opaco del producto en este ítem")
    name: str
    brand: str | None = None
    image_url: str | None = None
    quantity: int


class ShoppingListSummary(BaseModel):
    id: int
    name: str
    created_at: datetime
    updated_at: datetime
    items_count: int
    budget: int | None = None


class ShoppingListListResponse(BaseModel):
    items: list[ShoppingListSummary]


class ShoppingListDetail(BaseModel):
    id: int
    name: str
    created_at: datetime
    updated_at: datetime
    budget: int | None = None
    items: list[ShoppingListItem]


class SupermarketCost(BaseModel):
    supermarket_code: str
    supermarket_name: str
    total_cost: float | None = Field(
        None, description="None cuando ningún ítem de la lista tiene precio en este supermercado"
    )
    items_priced: int = Field(..., description="Cuántos ítems de la lista sí tienen precio aquí")
    items_total: int
    is_complete: bool = Field(
        ..., description="True si TODOS los ítems de la lista tienen precio en este supermercado"
    )
    missing_item_ids: list[int] = Field(
        default_factory=list,
        description="Ids de los ítems de la lista que NO tienen precio en este supermercado",
    )


class ShoppingListCostResponse(BaseModel):
    list_id: int
    costs: list[SupermarketCost]
    best_supermarket_code: str | None = Field(
        None,
        description="Supermercado más económico entre los que tienen la lista COMPLETA; "
        "None si ninguno la tiene completa",
    )


class DistributedPlanItem(BaseModel):
    item_id: int
    name: str
    quantity: int
    unit_price: float
    subtotal: float


class DistributedPlanStop(BaseModel):
    supermarket_code: str
    supermarket_name: str
    items: list[DistributedPlanItem]
    subtotal: float


class ShoppingListDistributedResponse(BaseModel):
    list_id: int
    total_cost: float | None = Field(
        None, description="None si ningún ítem de la lista tiene precio en ningún supermercado"
    )
    stops: list[DistributedPlanStop] = Field(default_factory=list)
    unpriced_item_ids: list[int] = Field(
        default_factory=list,
        description="Ítems sin precio en NINGÚN supermercado -- nunca se fuerzan a $0",
    )


class SwapAlternative(BaseModel):
    product_id: str = Field(..., description="ID opaco del producto sustituto ('sp-<id>')")
    name: str
    brand: str | None = None
    image_url: str | None = None
    unit_price: float
    supermarket_code: str
    supermarket_name: str


class SwapSuggestion(BaseModel):
    item_id: int
    item_name: str
    quantity: int
    current_unit_price: float = Field(..., description="Mejor precio actual del ítem en los supermercados al alcance")
    current_supermarket_name: str
    alternative: SwapAlternative
    saving_total: float = Field(..., description="Ahorro estimado al cambiar, multiplicado por la cantidad")


class SwapSuggestionsResponse(BaseModel):
    list_id: int
    suggestions: list[SwapSuggestion]
    total_saving: float


class SingleStoreReplacement(BaseModel):
    item_id: int
    item_name: str
    quantity: int
    substitute: SwapAlternative | None = Field(
        None, description="Producto parecido que sí vende este supermercado; null si no hay uno claro"
    )


class SingleStoreOption(BaseModel):
    supermarket_code: str
    supermarket_name: str
    items_total: int
    items_priced: int = Field(..., description="Cuántos ítems de la lista ya tienen precio aquí, tal cual")
    current_total: float = Field(..., description="Costo de los ítems que sí tienen precio aquí")
    completable: bool = Field(..., description="True si a todo lo que falta se le encontró un reemplazo")
    total_if_replaced: float | None = Field(
        None, description="Costo de la lista completa en este supermercado con los reemplazos; null si no es completable"
    )
    replacements: list[SingleStoreReplacement] = Field(default_factory=list)


class SingleStoreResponse(BaseModel):
    list_id: int
    options: list[SingleStoreOption]
