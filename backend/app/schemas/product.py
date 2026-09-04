from pydantic import BaseModel, Field

from app.schemas.common import PageInfo


class ProductListItem(BaseModel):
    id: str = Field(..., description="ID opaco del producto (usar tal cual en otros endpoints)")
    name: str
    brand: str | None = None
    image_url: str | None = None
    supermarket_code: str
    supermarket_name: str
    price: float | None = None
    list_price: float | None = None
    currency: str | None = None
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
