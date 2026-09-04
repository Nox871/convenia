"""Lógica de negocio de productos y comparación de precios.

Esta capa es la única que routers/ debe llamar. No conoce SQL ni HTTP: recibe
una conexión y parámetros ya validados por Pydantic, orquesta los
repositorios, y devuelve/valida las reglas de negocio (moneda, disponibilidad,
mejor precio). Si mañana el listado pasa a basarse en `products` en vez de
`source_products`, solo cambian los repositorios — esta capa y los routers
quedan igual.
"""
from __future__ import annotations

import logging

from sqlalchemy.engine import Connection

from app.core.exceptions import InvalidParameterError, NotFoundError
from app.core.product_ref import parse_product_ref
from app.repositories import price_repository, product_repository
from app.schemas.common import PageInfo
from app.schemas.price import CompareResponse, PriceOffer, ProductPricesResponse, ProductRef
from app.schemas.product import ProductDetail, ProductListItem, ProductListResponse

logger = logging.getLogger("app.services.product")


def list_products(
    conn: Connection,
    q: str | None,
    supermarket: str | None,
    page: int,
    limit: int,
) -> ProductListResponse:
    if page < 1:
        raise InvalidParameterError("'page' debe ser >= 1")
    if limit < 1:
        raise InvalidParameterError("'limit' debe ser >= 1")

    q = q.strip() if q else None
    if q == "":
        q = None

    supermarket_code = supermarket.strip().upper() if supermarket else None

    offset = (page - 1) * limit
    items, total = product_repository.search_source_products(
        conn, q=q, supermarket_code=supermarket_code, offset=offset, limit=limit
    )

    return ProductListResponse(
        items=[ProductListItem(**item) for item in items],
        pagination=PageInfo.build(page=page, limit=limit, total=total),
    )


def get_product_detail(conn: Connection, product_id_raw: str) -> ProductDetail:
    ref = _parse_ref_or_400(product_id_raw)

    if ref.kind == "source":
        data = product_repository.get_source_product_detail(conn, ref.numeric_id)
    else:
        data = product_repository.get_canonical_product_detail(conn, ref.numeric_id)

    if data is None:
        raise NotFoundError(f"Producto '{product_id_raw}' no existe")

    return ProductDetail(**data)


def get_product_prices(conn: Connection, product_id_raw: str) -> ProductPricesResponse:
    ref = _parse_ref_or_400(product_id_raw)
    _ensure_product_exists(conn, ref, product_id_raw)

    source_product_ids = product_repository.resolve_source_product_ids(conn, ref)
    offers_raw = price_repository.get_latest_offers(conn, source_product_ids)

    offers = [_to_price_offer(row) for row in offers_raw]
    return ProductPricesResponse(product_id=product_id_raw, offers=offers)


def compare_product(conn: Connection, product_id_raw: str) -> CompareResponse:
    ref = _parse_ref_or_400(product_id_raw)

    if ref.kind == "source":
        detail = product_repository.get_source_product_detail(conn, ref.numeric_id)
    else:
        detail = product_repository.get_canonical_product_detail(conn, ref.numeric_id)

    if detail is None:
        raise NotFoundError(f"Producto '{product_id_raw}' no existe")

    source_product_ids = product_repository.resolve_source_product_ids(conn, ref)
    offers_raw = price_repository.get_latest_offers(conn, source_product_ids)
    offers = [_to_price_offer(row) for row in offers_raw]

    best_price = _pick_best_price(offers)

    return CompareResponse(
        product=ProductRef(id=detail["id"], name=detail["name"]),
        offers=offers,
        best_price=best_price,
    )


# ---------------------------------------------------------------------- #
# Helpers internos
# ---------------------------------------------------------------------- #
def _parse_ref_or_400(product_id_raw: str):
    try:
        return parse_product_ref(product_id_raw)
    except ValueError as exc:
        raise InvalidParameterError(str(exc)) from exc


def _ensure_product_exists(conn: Connection, ref, product_id_raw: str) -> None:
    if ref.kind == "source":
        exists = product_repository.get_source_product_detail(conn, ref.numeric_id)
    else:
        exists = product_repository.get_canonical_product_detail(conn, ref.numeric_id)
    if exists is None:
        raise NotFoundError(f"Producto '{product_id_raw}' no existe")


def _to_price_offer(row: dict) -> PriceOffer:
    return PriceOffer(
        supermarket_code=row["supermarket_code"],
        supermarket_name=row["supermarket_name"],
        price=float(row["price"]),
        list_price=float(row["list_price"]) if row["list_price"] is not None else None,
        currency=row["currency"].strip(),
        available=row["available"],
        observed_at=row["observed_at"],
        payment_methods=row["payment_methods"] or [],
    )


def _pick_best_price(offers: list[PriceOffer]) -> PriceOffer | None:
    """Menor precio disponible, respetando moneda.

    Si todas las ofertas comparten moneda (caso actual: siempre COP), es un
    mínimo simple. Si llegaran a coexistir monedas distintas, se compara sólo
    dentro del grupo de la moneda más frecuente para no comparar peras con
    manzanas, y se deja constancia en el log (no debería ocurrir hoy).
    """
    if not offers:
        return None

    currencies = {offer.currency for offer in offers}
    if len(currencies) > 1:
        logger.warning(
            "Ofertas con monedas mixtas al comparar precios: %s", currencies
        )
        dominant_currency = max(currencies, key=lambda c: sum(1 for o in offers if o.currency == c))
        candidates = [o for o in offers if o.currency == dominant_currency]
    else:
        candidates = offers

    return min(candidates, key=lambda o: o.price)
