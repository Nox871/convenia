from pydantic import BaseModel, Field


class SupermarketCoverage(BaseModel):
    code: str
    name: str
    in_range: bool
    stores_in_range: int
    nearest_km: float | None = None


class CoverageResponse(BaseModel):
    radius_km: float
    supermarkets: list[SupermarketCoverage]


class CreatePhysicalStore(BaseModel):
    """Alta manual de un establecimiento -- sólo para administradores,
    para cubrir tiendas reales que el scraper de OpenStreetMap todavía no
    tiene (ej. una D1 nueva que aún no aparece en el mapa)."""

    supermarket_code: str = Field(..., description="Código del supermercado, ej. 'D1'")
    name: str = Field(..., min_length=1)
    address: str | None = None
    city: str | None = None
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class PhysicalStore(BaseModel):
    id: int
    supermarket_code: str
    supermarket_name: str
    name: str
    address: str | None = None
    city: str | None = None
    latitude: float | None = None
    longitude: float | None = None


class NearbyStore(PhysicalStore):
    distance_km: float
    walking_minutes: int


class StoreListResponse(BaseModel):
    items: list[PhysicalStore]


class NearbyStoreListResponse(BaseModel):
    items: list[NearbyStore]
