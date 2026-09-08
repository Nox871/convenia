from pydantic import BaseModel, Field


class Category(BaseModel):
    bucket: str = Field(..., description="Categoría común normalizada (ej. 'lacte', 'verdur')")
    products_count: int = Field(..., description="Productos activos en esta categoría común")
    supermarkets: list[str] = Field(
        default_factory=list,
        description="Códigos de supermercados que tienen al menos una categoría de origen en este bucket",
    )


class CategoryListResponse(BaseModel):
    items: list[Category]
