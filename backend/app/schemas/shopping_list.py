from datetime import datetime

from pydantic import BaseModel, Field, model_validator


class ShoppingListCreate(BaseModel):
    owner_ref: str = Field(..., description="Identificador de dispositivo de quien crea la lista")
    name: str


class ShoppingListRename(BaseModel):
    name: str


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


class ShoppingListListResponse(BaseModel):
    items: list[ShoppingListSummary]


class ShoppingListDetail(BaseModel):
    id: int
    name: str
    created_at: datetime
    updated_at: datetime
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
