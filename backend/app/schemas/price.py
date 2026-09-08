from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.common import PageInfo


class PriceOffer(BaseModel):
    supermarket_code: str
    supermarket_name: str
    # Nulos cuando el supermercado no tiene oferta para este producto:
    # nunca se representa como precio 0, sino como ausencia de dato.
    price: float | None = None
    list_price: float | None = None
    currency: str | None = None
    available: bool | None = None
    observed_at: datetime | None = None
    payment_methods: list[dict] = Field(default_factory=list)
    is_stale: bool = Field(
        False, description="True si observed_at supera el umbral de frescura configurado"
    )
    unit_price: float | None = Field(
        None,
        description="Precio por unidad de medida normalizada ($/kg, $/L o $/unidad); "
        "None cuando la cantidad/unidad del producto no se pudo determinar",
    )
    unit_label: str | None = Field(
        None, description="Unidad de referencia del precio unitario, ej. '$/kg'"
    )


class ProductPricesResponse(BaseModel):
    product_id: str
    offers: list[PriceOffer]


class PriceHistoryPoint(BaseModel):
    price: float
    list_price: float | None = None
    currency: str
    available: bool
    observed_at: datetime


class PriceHistoryResponse(BaseModel):
    product_id: str
    min_price: float
    max_price: float
    avg_price: float
    current_price: float
    current_observed_at: datetime
    variation_percentage: float = Field(
        ..., description="Variación porcentual entre el primer y el último precio observado"
    )
    observations_count: int
    observations: list[PriceHistoryPoint]
    pagination: PageInfo


class PriceHistoryMonthlyPoint(BaseModel):
    month: str = Field(..., description="Mes en formato 'YYYY-MM'")
    min_price: float
    max_price: float
    avg_price: float
    observations_count: int


class PriceHistoryMonthlyResponse(BaseModel):
    product_id: str
    months: list[PriceHistoryMonthlyPoint] = Field(
        default_factory=list,
        description="Sólo meses con observaciones reales; nunca se rellenan meses vacíos con 0",
    )


class ProductRef(BaseModel):
    id: str
    name: str


class CompareResponse(BaseModel):
    product: ProductRef
    offers: list[PriceOffer]
    best_price: PriceOffer | None = Field(
        None, description="Oferta con el menor precio disponible; None si no hay ofertas"
    )
    is_partial: bool = Field(
        False,
        description="True si no todos los supermercados activos tienen datos para este producto",
    )
    savings_absolute: float | None = Field(
        None, description="Precio máximo comparable menos precio mínimo comparable"
    )
    savings_percentage: float | None = Field(
        None, description="Ahorro porcentual respecto al precio máximo comparable (la referencia)"
    )
    savings_reference: str = Field(
        "precio_maximo", description="Qué precio se usó como referencia del ahorro porcentual"
    )
