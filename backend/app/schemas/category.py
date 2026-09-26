from pydantic import BaseModel, Field


class Category(BaseModel):
    label: str = Field(..., description="Etiqueta legible (ej. 'Lácteos y huevos') -- también el valor a pasar como filtro ?category= al buscar productos")
    products_count: int = Field(..., description="Productos activos en esta categoría")
    supermarkets: list[str] = Field(
        default_factory=list,
        description="Códigos de supermercados que tienen al menos un producto en esta categoría",
    )


class CategoryListResponse(BaseModel):
    items: list[Category]
