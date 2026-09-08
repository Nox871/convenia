from pydantic import BaseModel


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
