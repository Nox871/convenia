from pydantic import BaseModel, Field


class PageInfo(BaseModel):
    page: int = Field(..., description="Página actual (1-indexada)")
    limit: int = Field(..., description="Cantidad de resultados por página")
    total: int = Field(..., description="Total de resultados que cumplen el filtro")
    total_pages: int = Field(..., description="Total de páginas disponibles")
    has_next: bool = Field(..., description="Si existe una página siguiente")
    has_prev: bool = Field(..., description="Si existe una página anterior")

    @classmethod
    def build(cls, page: int, limit: int, total: int) -> "PageInfo":
        total_pages = (total + limit - 1) // limit if limit > 0 else 0
        return cls(
            page=page,
            limit=limit,
            total=total,
            total_pages=total_pages,
            has_next=page < total_pages,
            has_prev=page > 1,
        )
