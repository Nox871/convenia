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
import re
from datetime import datetime, timezone

from sqlalchemy.engine import Connection

from app.core.config import settings
from app.core.exceptions import InvalidParameterError, NotFoundError
from app.core.product_ref import parse_product_ref
from app.repositories import price_repository, product_repository
from app.schemas.common import PageInfo
from app.schemas.price import (
    CompareResponse,
    PriceHistoryMonthlyPoint,
    PriceHistoryMonthlyResponse,
    PriceHistoryPoint,
    PriceHistoryResponse,
    PriceOffer,
    ProductPricesResponse,
    ProductRef,
)
from app.schemas.product import ProductDetail, ProductListItem, ProductListResponse

logger = logging.getLogger("app.services.product")


_VALID_SORTS = {"price", "recent"}


def list_products(
    conn: Connection,
    q: str | None,
    supermarket: str | None,
    sort: str,
    page: int,
    limit: int,
) -> ProductListResponse:
    if page < 1:
        raise InvalidParameterError("'page' debe ser >= 1")
    if limit < 1:
        raise InvalidParameterError("'limit' debe ser >= 1")
    if sort not in _VALID_SORTS:
        raise InvalidParameterError(f"'sort' debe ser uno de: {', '.join(sorted(_VALID_SORTS))}")

    q = q.strip() if q else None
    if q == "":
        q = None

    supermarket_code = supermarket.strip().upper() if supermarket else None

    offset = (page - 1) * limit
    items, total = product_repository.search_products_grouped(
        conn, q=q, supermarket_code=supermarket_code, sort=sort, offset=offset, limit=limit
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
    # Una fila por CADA supermercado activo (no sólo los que tienen oferta),
    # y el número de filas nunca se asume fijo.
    offers_raw = price_repository.get_offers_for_compare(conn, source_product_ids)
    offers = [_to_price_offer(row) for row in offers_raw]

    # Precio unitario: sólo cuando el producto es canónico y su
    # cantidad/unidad se pudo extraer con confianza -- nunca se estima ni
    # se inventa para productos sin esa señal.
    if ref.kind == "canonical":
        cantidad_unidad = product_repository.get_canonical_quantity_unit(conn, ref.numeric_id)
        if cantidad_unidad:
            offers = [
                _with_unit_price(offer, cantidad_unidad["quantity"], cantidad_unidad["unit"])
                for offer in offers
            ]

    con_datos = [o for o in offers if o.price is not None]
    best_price = _pick_best_price(con_datos)
    savings_absolute, savings_percentage = _calculate_savings(con_datos)

    return CompareResponse(
        product=ProductRef(id=detail["id"], name=detail["name"]),
        offers=offers,
        best_price=best_price,
        is_partial=len(con_datos) < len(offers),
        savings_absolute=savings_absolute,
        savings_percentage=savings_percentage,
    )


def get_price_history(
    conn: Connection,
    product_id_raw: str,
    page: int,
    limit: int,
    month: str | None = None,
) -> PriceHistoryResponse:
    if page < 1:
        raise InvalidParameterError("'page' debe ser >= 1")
    if limit < 1:
        raise InvalidParameterError("'limit' debe ser >= 1")
    if month is not None and not re.fullmatch(r"\d{4}-\d{2}", month):
        raise InvalidParameterError("'month' debe tener el formato 'YYYY-MM'")

    ref = _parse_ref_or_400(product_id_raw)
    _ensure_product_exists(conn, ref, product_id_raw)

    source_product_ids = product_repository.resolve_source_product_ids(conn, ref)
    resumen = price_repository.get_price_history_summary(conn, source_product_ids)
    if resumen is None:
        raise NotFoundError(
            f"Producto '{product_id_raw}' no tiene observaciones de precio registradas"
        )

    offset = (page - 1) * limit
    observaciones_raw, total = price_repository.get_price_history_observations(
        conn, source_product_ids, offset, limit, month=month
    )

    primer_precio = float(resumen["first_price"])
    precio_actual = float(resumen["current_price"])
    variacion = (
        ((precio_actual - primer_precio) / primer_precio) * 100 if primer_precio else 0.0
    )

    return PriceHistoryResponse(
        product_id=product_id_raw,
        min_price=float(resumen["min_price"]),
        max_price=float(resumen["max_price"]),
        avg_price=float(resumen["avg_price"]),
        current_price=precio_actual,
        current_observed_at=resumen["current_observed_at"],
        variation_percentage=round(variacion, 2),
        observations_count=resumen["observations_count"],
        observations=[
            PriceHistoryPoint(
                price=float(row["price"]),
                list_price=float(row["list_price"]) if row["list_price"] is not None else None,
                currency=row["currency"].strip(),
                available=row["available"],
                observed_at=row["observed_at"],
            )
            for row in observaciones_raw
        ],
        pagination=PageInfo.build(page=page, limit=limit, total=total),
    )


def get_price_history_monthly(conn: Connection, product_id_raw: str) -> PriceHistoryMonthlyResponse:
    """Agregados mensuales para el historial visual (barras + drill-down).
    Meses sin observaciones no aparecen -- nunca se rellenan con 0."""
    ref = _parse_ref_or_400(product_id_raw)
    _ensure_product_exists(conn, ref, product_id_raw)

    source_product_ids = product_repository.resolve_source_product_ids(conn, ref)
    meses_raw = price_repository.get_price_history_monthly(conn, source_product_ids)

    return PriceHistoryMonthlyResponse(
        product_id=product_id_raw,
        months=[
            PriceHistoryMonthlyPoint(
                month=row["month"],
                min_price=float(row["min_price"]),
                max_price=float(row["max_price"]),
                avg_price=float(row["avg_price"]),
                observations_count=row["observations_count"],
            )
            for row in meses_raw
        ],
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
    observed_at = row["observed_at"]
    is_stale = False
    if observed_at is not None:
        # `observed_at` es TIMESTAMPTZ (tz-aware); se compara contra "ahora"
        # en UTC para no depender de la zona horaria del proceso.
        antiguedad_horas = (datetime.now(timezone.utc) - observed_at).total_seconds() / 3600
        is_stale = antiguedad_horas > settings.data_freshness_threshold_hours

    return PriceOffer(
        supermarket_code=row["supermarket_code"],
        supermarket_name=row["supermarket_name"],
        price=float(row["price"]) if row["price"] is not None else None,
        list_price=float(row["list_price"]) if row["list_price"] is not None else None,
        currency=row["currency"].strip() if row["currency"] else None,
        available=row["available"],
        observed_at=observed_at,
        payment_methods=row["payment_methods"] or [],
        is_stale=is_stale,
    )


_UNIDAD_REFERENCIA = {"g": ("kg", 1000), "ml": ("L", 1000), "un": ("unidad", 1)}


def _with_unit_price(offer: PriceOffer, quantity, unit: str) -> PriceOffer:
    """Copia `offer` agregando `unit_price`/`unit_label` si `unit` es una
    dimensión reconocida y hay precio con qué calcularlo."""
    referencia = _UNIDAD_REFERENCIA.get(unit)
    if referencia is None or offer.price is None or not quantity:
        return offer

    etiqueta_unidad, factor = referencia
    cantidad_en_referencia = float(quantity) / factor
    if cantidad_en_referencia <= 0:
        return offer

    return offer.model_copy(
        update={
            "unit_price": round(offer.price / cantidad_en_referencia, 2),
            "unit_label": f"$/{etiqueta_unidad}",
        }
    )


def _calculate_savings(offers: list[PriceOffer]) -> tuple[float | None, float | None]:
    """Ahorro absoluto y porcentual entre el precio máximo y mínimo
    comparables. La referencia del porcentaje es el precio máximo --
    documentado también en `CompareResponse.savings_reference`."""
    if len(offers) < 2:
        return None, None

    precios = [o.price for o in offers if o.price is not None]
    if len(precios) < 2:
        return None, None

    maximo, minimo = max(precios), min(precios)
    ahorro_absoluto = maximo - minimo
    ahorro_porcentual = (ahorro_absoluto / maximo) * 100 if maximo else 0.0
    return round(ahorro_absoluto, 2), round(ahorro_porcentual, 2)


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
