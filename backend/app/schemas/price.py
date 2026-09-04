from datetime import datetime

from pydantic import BaseModel, Field


class PriceOffer(BaseModel):
    supermarket_code: str
    supermarket_name: str
    price: float
    list_price: float | None = None
    currency: str
    available: bool
    observed_at: datetime
    payment_methods: list[dict] = Field(default_factory=list)


class ProductPricesResponse(BaseModel):
    product_id: str
    offers: list[PriceOffer]


class ProductRef(BaseModel):
    id: str
    name: str


class CompareResponse(BaseModel):
    product: ProductRef
    offers: list[PriceOffer]
    best_price: PriceOffer | None = Field(
        None, description="Oferta con el menor precio disponible; None si no hay ofertas"
    )
