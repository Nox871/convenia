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
import time
from datetime import datetime, timezone

from sqlalchemy.engine import Connection

from app.core.category_bucket import ETIQUETAS_AMIGABLES
from app.core.config import settings
from app.core.exceptions import InvalidParameterError, NotFoundError
from app.core.product_ref import parse_product_ref
from app.core import basket as basket_core
from app.core.query_parser import interpretar, sin_tildes, termino_de_busqueda
from app.core.spelling import sugerir_busqueda
from app.repositories import price_repository, product_repository, search_term_repository
from app.services import category_service
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
from app.schemas.product import (
    ProductDetail,
    ProductListItem,
    ProductListResponse,
    BasketLine,
    BasketResponse,
    DidYouMeanResponse,
    PopularSearch,
    PopularSearchesResponse,
    ProductSuggestResponse,
    ProductSuggestion,
)

logger = logging.getLogger("app.services.product")


_VALID_SORTS = {"price", "recent"}


def list_products(
    conn: Connection,
    q: str | None,
    supermarket: str | None,
    sort: str,
    page: int,
    limit: int,
    category: str | None = None,
    supermarket_codes: list[str] | None = None,
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

    category_source_ids = None
    if category:
        label = category.strip()
        if label not in ETIQUETAS_AMIGABLES.values():
            raise InvalidParameterError(f"'category' desconocida: '{category}'")
        category_source_ids = category_service.source_product_ids_for_label(conn, label)

    supermarket_code = supermarket.strip().upper() if supermarket else None

    offset = (page - 1) * limit
    items, total = product_repository.search_products_grouped(
        conn,
        q=q,
        category_source_ids=category_source_ids,
        supermarket_codes=supermarket_codes,
        supermarket_code=supermarket_code,
        sort=sort,
        offset=offset,
        limit=limit,
    )

    _count_search(conn, q, category, page, total)
    return ProductListResponse(
        items=[ProductListItem(**item) for item in items],
        pagination=PageInfo.build(page=page, limit=limit, total=total),
    )


_VOCAB_CACHE: dict[tuple[str, ...] | None, tuple[float, dict[str, int]]] = {}
_VOCAB_TTL_SEGUNDOS = 3600


def _vocabulario(conn: Connection, supermarket_codes: list[str] | None) -> dict[str, int]:
    """Vocabulario de nombres por alcance de supermercados, en memoria una hora
    (cambia una vez al día, con la carga; recalcularlo por búsqueda sería caro)."""
    clave = None if supermarket_codes is None else tuple(sorted(supermarket_codes))
    guardado = _VOCAB_CACHE.get(clave)
    ahora = time.monotonic()
    if guardado is not None and ahora - guardado[0] < _VOCAB_TTL_SEGUNDOS:
        return guardado[1]
    vocab = product_repository.get_name_vocabulary(conn, supermarket_codes)
    _VOCAB_CACHE[clave] = (ahora, vocab)
    return vocab


def did_you_mean(
    conn: Connection, q: str, supermarket_codes: list[str] | None = None
) -> DidYouMeanResponse:
    """"¿Quisiste decir Arroz?": corrige palabras mal escritas ("aroz", "arros")
    con el vocabulario de los productos disponibles. `suggestion` es None si el
    texto ya está bien escrito o no hay nada parecido."""
    q = q.strip()
    if not q:
        raise InvalidParameterError("'q' no puede estar vacío")
    if supermarket_codes is not None and not supermarket_codes:
        return DidYouMeanResponse(query=q, suggestion=None)
    return DidYouMeanResponse(
        query=q, suggestion=sugerir_busqueda(q, _vocabulario(conn, supermarket_codes))
    )


def suggest_products(
    conn: Connection,
    q: str,
    limit: int,
    prefer: str = "comparable",
    supermarket_codes: list[str] | None = None,
) -> ProductSuggestResponse:
    """Sugerencias por similitud de texto, para entrada por voz/OCR o texto
    con errores. No reemplaza la búsqueda normal (`list_products`): se usa
    cuando el texto no es exacto y hace falta que el usuario confirme cuál
    de varios parecidos es el producto real."""
    q = q.strip()
    if not q:
        raise InvalidParameterError("'q' no puede estar vacío")
    if limit < 1:
        raise InvalidParameterError("'limit' debe ser >= 1")

    if prefer not in ("comparable", "price"):
        raise InvalidParameterError("'prefer' debe ser 'comparable' o 'price'")

    consulta = interpretar(q)
    rows = product_repository.search_products_fuzzy(
        conn,
        q=consulta.texto or q,  # sin las cantidades ni el relleno ("huevos 30 und" -> "huevos")
        limit=limit,
        prefer=prefer,
        supermarket_codes=supermarket_codes,
        cantidad_regex=consulta.cantidad_regex,
    )
    return ProductSuggestResponse(
        query=q,
        suggestions=[ProductSuggestion(**row) for row in rows],
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


def get_product_prices(
    conn: Connection, product_id_raw: str, supermarket_codes: list[str] | None = None
) -> ProductPricesResponse:
    ref = _parse_ref_or_400(product_id_raw)
    _ensure_product_exists(conn, ref, product_id_raw)

    source_product_ids = product_repository.resolve_source_product_ids(conn, ref)
    offers_raw = price_repository.get_latest_offers(conn, source_product_ids, supermarket_codes)

    offers = [_to_price_offer(row) for row in offers_raw]
    return ProductPricesResponse(product_id=product_id_raw, offers=offers)


def compare_product(
    conn: Connection, product_id_raw: str, supermarket_codes: list[str] | None = None
) -> CompareResponse:
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
    offers_raw = price_repository.get_offers_for_compare(conn, source_product_ids, supermarket_codes)
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
    supermarket_codes: list[str] | None = None,
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
    resumen = price_repository.get_price_history_summary(
        conn, source_product_ids, supermarket_codes
    )
    if resumen is None and supermarket_codes is not None:
        # Ninguna tienda del rango tiene precios de este producto: se muestra el
        # historial completo en vez de "Sin historial" (el producto sí lo tiene).
        supermarket_codes = None
        resumen = price_repository.get_price_history_summary(conn, source_product_ids, None)
    if resumen is None:
        raise NotFoundError(
            f"Producto '{product_id_raw}' no tiene observaciones de precio registradas"
        )

    offset = (page - 1) * limit
    observaciones_raw, total = price_repository.get_price_history_observations(
        conn, source_product_ids, offset, limit, month=month, supermarket_codes=supermarket_codes
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


def get_price_history_monthly(
    conn: Connection, product_id_raw: str, supermarket_codes: list[str] | None = None
) -> PriceHistoryMonthlyResponse:
    """Agregados mensuales para el historial visual (barras + drill-down).
    Meses sin observaciones no aparecen -- nunca se rellenan con 0."""
    ref = _parse_ref_or_400(product_id_raw)
    _ensure_product_exists(conn, ref, product_id_raw)

    source_product_ids = product_repository.resolve_source_product_ids(conn, ref)
    meses_raw = price_repository.get_price_history_monthly(
        conn, source_product_ids, supermarket_codes
    )
    if not meses_raw and supermarket_codes is not None:
        meses_raw = price_repository.get_price_history_monthly(conn, source_product_ids, None)

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
_UNIDAD_PEQUENA = {"kg": "$/100 g", "L": "$/100 ml"}
_UMBRAL_PRECIO_UNITARIO_GRANDE = 50_000


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

    precio_unitario = offer.price / cantidad_en_referencia
    etiqueta = f"$/{etiqueta_unidad}"
    # Un frasco de 50 g a $12.000 daba "$240.000 $/kg": correcto, pero absurdo
    # a la vista. Cuando el precio por kg o por litro pasa de $50.000 se muestra
    # por 100 g / 100 ml, la referencia que usan los supermercados en esos casos.
    if etiqueta_unidad in _UNIDAD_PEQUENA and precio_unitario >= _UMBRAL_PRECIO_UNITARIO_GRANDE:
        precio_unitario /= 10
        etiqueta = _UNIDAD_PEQUENA[etiqueta_unidad]

    return offer.model_copy(
        update={"unit_price": round(precio_unitario, 2), "unit_label": etiqueta}
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


def build_basket(
    conn: Connection,
    terms: list[str],
    tier: str = "medio",
    budget: float | None = None,
    supermarket_codes: list[str] | None = None,
) -> BasketResponse:
    """Arma una lista para un nivel de gasto y, opcionalmente, un presupuesto:
    elige un producto real por cada término y decide cuántas unidades llevar
    (ver `app.core.basket`). El orden de `terms` es su prioridad."""
    terms = [t.strip() for t in terms if t and t.strip()][:30]
    if not terms:
        raise InvalidParameterError("'terms' no puede estar vacío")
    if tier not in basket_core.NIVELES:
        raise InvalidParameterError(f"'tier' debe ser uno de: {', '.join(basket_core.NIVELES)}")
    if budget is not None and budget <= 0:
        raise InvalidParameterError("'budget' debe ser mayor que 0")

    por_termino: list[tuple[str, list[basket_core.Candidato]]] = []
    for termino in terms:
        items, _total = product_repository.search_products_grouped(
            conn, q=termino, supermarket_code=None, sort="price", offset=0, limit=40,
            supermarket_codes=supermarket_codes,
        )
        consulta = interpretar(termino)
        primera = consulta.palabras[0] if consulta.palabras else None
        # Sólo productos que SON lo pedido ("Mantequilla Alpina"), no los que lo
        # mencionan ("Saltinas de mantequilla"); si no hay ninguno, los que lo traen
        # como palabra.
        nombres = [(i, sin_tildes(i["name"])) for i in items if i["price"]]
        propios = [i for i, n in nombres if primera and n.startswith(primera)]
        if not propios:
            propios = [i for i, n in nombres if primera and f" {primera} " in f" {n} "]
        elegibles = propios or [i for i in items if i["price"]]
        por_termino.append((termino, [
            basket_core.Candidato(id=i["id"], name=i["name"], price=float(i["price"]),
                                  offers_count=int(i["offers_count"] or 1), data=i)
            for i in elegibles
        ]))

    canasta = basket_core.armar(por_termino, nivel=tier, presupuesto=budget)
    quitados = set(canasta.sin_presupuesto_para)
    lineas = [
        BasketLine(
            term=l.termino,
            found=l.candidato is not None,
            product=ProductListItem(**l.candidato.data) if l.candidato else None,
            quantity=l.cantidad,
            subtotal=round(l.subtotal, 2),
        )
        for l in canasta.lineas
    ]
    return BasketResponse(
        tier_requested=canasta.nivel_pedido,
        tier_used=canasta.nivel_usado,
        budget=budget,
        total=round(canasta.total, 2),
        remaining=None if canasta.sobrante is None else round(canasta.sobrante, 2),
        exceeds_budget=canasta.excede_presupuesto,
        dropped_terms=[t for t in terms if t in quitados],
        items=lineas,
    )


# Una búsqueda sólo cuenta como frecuente cuando la han hecho al menos esta
# cantidad de veces: así una búsqueda suelta no aparece en el inicio de todos.
MIN_BUSQUEDAS_FRECUENTES = 3


def popular_searches(conn: Connection, limit: int = 6) -> PopularSearchesResponse:
    """Lo que más se busca en la app, para las sugerencias del inicio."""
    if limit < 1:
        raise InvalidParameterError("'limit' debe ser >= 1")
    rows = search_term_repository.top(conn, limit=limit, min_searches=MIN_BUSQUEDAS_FRECUENTES)
    return PopularSearchesResponse(items=[PopularSearch(**r) for r in rows])


def _count_search(conn: Connection, q: str | None, category: str | None, page: int, total: int) -> None:
    """Cuenta la búsqueda para las frecuentes. Es un extra: si falla, la búsqueda
    de la persona no se ve afectada."""
    if not q or category or page != 1 or total <= 0:
        return
    termino = termino_de_busqueda(q)
    if termino is None:
        return
    try:
        search_term_repository.record(conn, *termino)
    except Exception:  # noqa: BLE001 - un contador roto no debe romper la búsqueda
        logger.warning("No se pudo contar la búsqueda %r", q, exc_info=True)
        try:
            conn.rollback()
        except Exception:  # noqa: BLE001
            pass
