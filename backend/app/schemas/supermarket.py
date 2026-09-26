from datetime import datetime

from pydantic import BaseModel, Field


class Supermarket(BaseModel):
    id: int
    code: str
    name: str
    website_url: str | None = None
    currency: str
    is_active: bool
    created_at: datetime
    last_successful_run_at: datetime | None = Field(
        None, description="Fecha/hora de la última ejecución de scraping exitosa"
    )


class SupermarketListResponse(BaseModel):
    items: list[Supermarket]
