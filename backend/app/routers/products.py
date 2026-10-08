from fastapi import APIRouter, Depends, Query
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.core.scope import parse_supermarket_scope
from app.schemas.product import (
    BasketResponse,
    DidYouMeanResponse,
    PopularSearchesResponse,
    ProductDetail,
    ProductListResponse,
    ProductSuggestResponse,
)
from app.services import product_service

router = APIRouter(prefix="/api/v1/products", tags=["products"])


@router.get("", response_model=ProductListResponse)
def list_products(
    q: str | None = Query(None, description="Texto de búsqueda por nombre de producto"),
    category: str | None = Query(
        None, description="Filtrar por etiqueta de categoría devuelta por /categories, ej. 'Lácteos y huevos'"
    ),
    supermarket: str | None = Query(
        None, description="Filtrar por código de supermercado, ej. 'D1' o 'EXITO'"
    ),
    sort: str = Query(
        "price", description="Criterio de orden: 'price' (menor precio) o 'recent' (más reciente)"
    ),
    page: int = Query(1, ge=1, description="Página, 1-indexada"),
    limit: int = Query(20, ge=1, le=100, description="Resultados por página (máx. 100)"),
    scope: list[str] | None = Depends(parse_supermarket_scope),
    conn: Connection = Depends(get_db),
):
    return product_service.list_products(
        conn,
        q=q,
        category=category,
        supermarket=supermarket,
        sort=sort,
        page=page,
        limit=limit,
        supermarket_codes=scope,
    )


@router.get("/suggest", response_model=ProductSuggestResponse)
def suggest_products(
    q: str = Query(..., description="Texto a buscar por similitud (voz, OCR, o texto con errores)"),
    limit: int = Query(5, ge=1, le=20, description="Máximo de sugerencias a devolver"),
    prefer: str = Query(
        "comparable",
        description="Criterio entre empates: 'comparable' (más supermercados) o 'price' (más barato)",
    ),
    scope: list[str] | None = Depends(parse_supermarket_scope),
    conn: Connection = Depends(get_db),
):
    return product_service.suggest_products(
        conn, q=q, limit=limit, prefer=prefer, supermarket_codes=scope
    )


@router.get("/basket", response_model=BasketResponse)
def build_basket(
    terms: str = Query(..., description="Productos separados por '|', en orden de prioridad. Ej. 'pan|huevos|leche'"),
    tier: str = Query("medio", description="Nivel de gasto: 'economico', 'medio' o 'alto'"),
    budget: float | None = Query(None, gt=0, description="Presupuesto máximo en pesos (opcional)"),
    scope: list[str] | None = Depends(parse_supermarket_scope),
    conn: Connection = Depends(get_db),
):
    return product_service.build_basket(
        conn, terms=terms.split("|"), tier=tier, budget=budget, supermarket_codes=scope
    )


@router.get("/popular-searches", response_model=PopularSearchesResponse)
def popular_searches(
    limit: int = Query(6, ge=1, le=20, description="Cuántas búsquedas devolver"),
    conn: Connection = Depends(get_db),
):
    return product_service.popular_searches(conn, limit=limit)


@router.get("/did-you-mean", response_model=DidYouMeanResponse)
def did_you_mean(
    q: str = Query(..., description="Texto buscado, posiblemente con errores de ortografía"),
    scope: list[str] | None = Depends(parse_supermarket_scope),
    conn: Connection = Depends(get_db),
):
    return product_service.did_you_mean(conn, q=q, supermarket_codes=scope)


@router.get("/{product_id}", response_model=ProductDetail)
def get_product(product_id: str, conn: Connection = Depends(get_db)):
    return product_service.get_product_detail(conn, product_id)
