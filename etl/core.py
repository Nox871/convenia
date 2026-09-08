"""Motor genérico de ETL: RAW (D1 / Éxito / Carulla / Jumbo / Olímpica) -> PostgreSQL.

Todos los scrapers producen RAW con la misma forma de producto (product_id,
product_name, brand, category_id/category, price, list_price,
payment_methods, extracted_at, ...), así que la lógica de carga se comparte
por completo; lo único específico por supermercado es el código (`code`) y
el directorio donde ese conector deja sus snapshots RAW.

Además de cargar productos y precios, este motor:
- registra cada ejecución en `scraper_runs`,
- aplica el ciclo de vida de producto: productos vistos quedan/vuelven
  ACTIVE, los no vistos pasan a TEMPORARILY_UNAVAILABLE y, tras
  `PRODUCT_DISCONTINUATION_THRESHOLD_DAYS` sin aparecer, a DISCONTINUED,
- protege contra ejecuciones con muy pocos productos: un RAW
  sospechosamente pequeño marca el run como FAILED y no toca el ciclo de
  vida de ningún producto.
"""
from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone
from pathlib import Path

from psycopg2.extras import Json

_PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from scraper.core.raw_writer import resolver_ultimo_raw  # noqa: E402

from etl import db
from etl.common import (
    ETLStats,
    normalize_payment_methods,
    normalize_str,
    parse_timestamp,
    slugify,
    to_decimal,
)
from etl.config import (
    MIN_PRODUCTS_RATIO_VS_HISTORY,
    PRODUCT_DISCONTINUATION_THRESHOLD_DAYS,
)

logger = logging.getLogger("etl")


class RawValidationError(Exception):
    pass


class SupermarketETL:
    def __init__(self, code: str, raw_dir: Path):
        self.code = code
        self.raw_dir = Path(raw_dir)
        self.stats = ETLStats()
        self._category_cache: dict[str, int] = {}
        self.run_id: int | None = None

    # ------------------------------------------------------------------ #
    # Carga y validación del RAW
    # ------------------------------------------------------------------ #
    def _load_raw(self) -> tuple[dict, Path]:
        raw_path = resolver_ultimo_raw(self.raw_dir, self.code)

        with open(raw_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        if not isinstance(data, dict) or "products" not in data:
            raise RawValidationError(
                f"El RAW de {self.code} ({raw_path}) no tiene la forma esperada (falta 'products')"
            )
        if not isinstance(data["products"], list):
            raise RawValidationError(f"'products' en el RAW de {self.code} no es una lista")

        source = str(data.get("source", "")).strip().upper()
        if source and source != self.code:
            logger.warning(
                "El campo 'source' del RAW (%s) no coincide con el supermercado esperado (%s)",
                source,
                self.code,
            )

        return data, raw_path

    def _get_supermarket_id(self, conn) -> int:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM supermarkets WHERE code = %s", (self.code,))
            row = cur.fetchone()
        if row is None:
            raise RawValidationError(
                f"No existe el supermercado '{self.code}' en la tabla supermarkets"
            )
        return row[0]

    # ------------------------------------------------------------------ #
    # Ejecuciones (scraper_runs)
    # ------------------------------------------------------------------ #
    def _create_run(self, conn, supermarket_id: int, started_at, raw_location: str) -> int:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO scraper_runs (supermarket_id, started_at, status, raw_location)
                VALUES (%s, %s, 'RUNNING', %s)
                RETURNING id
                """,
                (supermarket_id, started_at, raw_location),
            )
            run_id = cur.fetchone()[0]
        conn.commit()
        return run_id

    def _average_historical_products(self, conn, supermarket_id: int) -> float | None:
        """Promedio de products_detected de los últimos 5 runs válidos, usado
        como referencia para el chequeo de calidad mínima (sección 31)."""
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT AVG(products_detected) FROM (
                    SELECT products_detected FROM scraper_runs
                    WHERE supermarket_id = %s
                      AND status IN ('SUCCESS', 'SUCCESS_WITH_ERRORS')
                      AND products_detected IS NOT NULL
                    ORDER BY started_at DESC
                    LIMIT 5
                ) recientes
                """,
                (supermarket_id,),
            )
            (promedio,) = cur.fetchone()
        return float(promedio) if promedio is not None else None

    def _finish_run(self, conn, run_id: int, status: str, finished_at, **counters) -> None:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE scraper_runs
                SET finished_at = %s,
                    status = %s,
                    products_detected = %s,
                    categories_detected = %s,
                    products_new = %s,
                    products_existing = %s,
                    products_missing = %s,
                    errors_count = %s
                WHERE id = %s
                """,
                (
                    finished_at,
                    status,
                    counters.get("products_detected"),
                    counters.get("categories_detected"),
                    counters.get("products_new"),
                    counters.get("products_existing"),
                    counters.get("products_missing"),
                    counters.get("errors_count", 0),
                    run_id,
                ),
            )
        conn.commit()

    # ------------------------------------------------------------------ #
    # Categorías
    # ------------------------------------------------------------------ #
    def _resolve_category_external_id(self, raw_category_id, category_name) -> str | None:
        if raw_category_id not in (None, ""):
            return str(raw_category_id).strip()
        if category_name:
            # D1 no siempre trae category_id: usamos una clave determinista basada
            # en el nombre real de la categoría en vez de inventar un ID.
            return f"slug:{slugify(category_name)}"
        return None

    def _upsert_category(self, conn, supermarket_id: int, external_id: str, name: str | None,
                          url: str | None) -> int:
        cache_key = external_id
        if cache_key in self._category_cache:
            return self._category_cache[cache_key]

        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO source_categories (supermarket_id, external_id, name_raw, url)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (supermarket_id, external_id) DO UPDATE SET
                    name_raw = EXCLUDED.name_raw,
                    url = COALESCE(EXCLUDED.url, source_categories.url)
                RETURNING id, (xmax = 0) AS inserted
                """,
                (supermarket_id, external_id, name or external_id, url),
            )
            category_id, inserted = cur.fetchone()

        self._category_cache[cache_key] = category_id
        self.stats.categories_seen += 1
        if inserted:
            self.stats.categories_new += 1
        return category_id

    # ------------------------------------------------------------------ #
    # Productos
    # ------------------------------------------------------------------ #
    def _upsert_source_product(self, conn, supermarket_id: int, source_category_id: int | None,
                                product: dict, extracted_at) -> tuple[int, bool]:
        external_id = normalize_str(product.get("product_id"))
        if not external_id:
            raise ValueError("product_id ausente o vacío")

        name_raw = normalize_str(product.get("product_name"))
        if not name_raw:
            raise ValueError(f"product_name ausente para product_id={external_id}")

        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO source_products (
                    supermarket_id, source_category_id, external_id, name_raw, brand_raw,
                    brand_external_id, product_reference, product_reference_code, product_url,
                    image_url, release_date, seller_name_raw, seller_external_id,
                    first_seen_at, last_seen_at, status, raw_data
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'ACTIVE', %s
                )
                ON CONFLICT (supermarket_id, external_id) DO UPDATE SET
                    source_category_id = EXCLUDED.source_category_id,
                    name_raw = EXCLUDED.name_raw,
                    brand_raw = EXCLUDED.brand_raw,
                    brand_external_id = EXCLUDED.brand_external_id,
                    product_reference = EXCLUDED.product_reference,
                    product_reference_code = EXCLUDED.product_reference_code,
                    product_url = EXCLUDED.product_url,
                    image_url = EXCLUDED.image_url,
                    release_date = EXCLUDED.release_date,
                    seller_name_raw = EXCLUDED.seller_name_raw,
                    seller_external_id = EXCLUDED.seller_external_id,
                    first_seen_at = LEAST(
                        COALESCE(source_products.first_seen_at, EXCLUDED.first_seen_at),
                        COALESCE(EXCLUDED.first_seen_at, source_products.first_seen_at)
                    ),
                    last_seen_at = GREATEST(
                        COALESCE(source_products.last_seen_at, EXCLUDED.last_seen_at),
                        COALESCE(EXCLUDED.last_seen_at, source_products.last_seen_at)
                    ),
                    -- Ver también, cada producto vuelto a ver queda/vuelve ACTIVE
                    -- (reactivación incluida) y se reinicia su contador de ausencias.
                    status = 'ACTIVE',
                    consecutive_missing_runs = 0,
                    discontinued_at = NULL,
                    raw_data = EXCLUDED.raw_data
                RETURNING id, (xmax = 0) AS inserted
                """,
                (
                    supermarket_id,
                    source_category_id,
                    external_id,
                    name_raw,
                    normalize_str(product.get("brand")),
                    normalize_str(product.get("brand_id")),
                    normalize_str(product.get("product_reference")),
                    normalize_str(product.get("product_reference_code")),
                    normalize_str(product.get("product_url")),
                    normalize_str(product.get("image_url")),
                    parse_timestamp(product.get("release_date")),
                    normalize_str(product.get("seller_name")),
                    normalize_str(product.get("seller_id")),
                    extracted_at,
                    extracted_at,
                    Json(product),
                ),
            )
            source_product_id, inserted = cur.fetchone()

        return source_product_id, inserted

    def _insert_price_observation(self, conn, source_product_id: int, product: dict,
                                   observed_at, run_id: int | None) -> bool:
        price = to_decimal(product.get("price"))
        if price is None:
            raise ValueError("price ausente: no se puede registrar price_observation")

        list_price = to_decimal(product.get("list_price"))
        currency = normalize_str(product.get("currency")) or "COP"
        payment_methods = normalize_payment_methods(product.get("payment_methods"))

        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO price_observations (
                    source_product_id, price, list_price, currency, available,
                    observed_at, payment_methods, scraper_run_id
                )
                SELECT %s, %s, %s, %s, TRUE, %s, %s, %s
                WHERE NOT EXISTS (
                    SELECT 1 FROM price_observations
                    WHERE source_product_id = %s AND observed_at = %s
                )
                RETURNING id
                """,
                (
                    source_product_id,
                    price,
                    list_price,
                    currency,
                    observed_at,
                    Json(payment_methods),
                    run_id,
                    source_product_id,
                    observed_at,
                ),
            )
            row = cur.fetchone()

        if row is not None:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE source_products SET last_price_at = %s WHERE id = %s",
                    (observed_at, source_product_id),
                )

        return row is not None

    # ------------------------------------------------------------------ #
    # Ciclo de vida del producto
    # ------------------------------------------------------------------ #
    def _apply_lifecycle(self, conn, supermarket_id: int, external_ids_vistos: list[str]) -> dict:
        """Marca como ausentes (y, tras el umbral de días, descontinuados) los
        productos ACTIVE o TEMPORARILY_UNAVAILABLE de este supermercado que NO
        estén en `external_ids_vistos`.

        Los productos vistos ya quedaron ACTIVE en `_upsert_source_product`
        (incluida la reactivación de los que estaban DISCONTINUED); esta
        función sólo se ocupa de los que faltaron en el RAW actual. Incluye
        TEMPORARILY_UNAVAILABLE (no sólo ACTIVE) a propósito: un producto ya
        marcado ausente debe seguir acumulando `consecutive_missing_runs` en
        cada corrida donde sigue sin aparecer, y sólo así puede eventualmente
        cruzar el umbral de días y pasar a DISCONTINUED -- si sólo se
        reevaluaran los ACTIVE, un producto ausente quedaría congelado en
        TEMPORARILY_UNAVAILABLE para siempre tras su primera ausencia.
        """
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE source_products
                SET consecutive_missing_runs = consecutive_missing_runs + 1,
                    status = CASE
                        WHEN now() - last_seen_at >= (%s || ' days')::interval
                        THEN 'DISCONTINUED'
                        ELSE 'TEMPORARILY_UNAVAILABLE'
                    END,
                    discontinued_at = CASE
                        WHEN now() - last_seen_at >= (%s || ' days')::interval
                        THEN now()
                        ELSE discontinued_at
                    END
                WHERE supermarket_id = %s
                  AND status IN ('ACTIVE', 'TEMPORARILY_UNAVAILABLE')
                  AND NOT (external_id = ANY(%s))
                RETURNING status
                """,
                (
                    PRODUCT_DISCONTINUATION_THRESHOLD_DAYS,
                    PRODUCT_DISCONTINUATION_THRESHOLD_DAYS,
                    supermarket_id,
                    external_ids_vistos,
                ),
            )
            filas = cur.fetchall()

        return {
            "missing": sum(1 for (status,) in filas if status == "TEMPORARILY_UNAVAILABLE"),
            "discontinued": sum(1 for (status,) in filas if status == "DISCONTINUED"),
        }

    # ------------------------------------------------------------------ #
    # Orquestación
    # ------------------------------------------------------------------ #
    def _process_product(self, conn, supermarket_id: int, product: dict) -> None:
        extracted_at = parse_timestamp(product.get("extracted_at"))
        if extracted_at is None:
            raise ValueError("extracted_at ausente o inválido")

        category_name = normalize_str(product.get("category"))
        category_url = normalize_str(product.get("source_category_url"))
        category_external_id = self._resolve_category_external_id(
            product.get("category_id"), category_name
        )

        source_category_id = None
        if category_external_id:
            source_category_id = self._upsert_category(
                conn, supermarket_id, category_external_id, category_name, category_url
            )

        source_product_id, inserted = self._upsert_source_product(
            conn, supermarket_id, source_category_id, product, extracted_at
        )
        if inserted:
            self.stats.products_inserted += 1
        else:
            self.stats.products_updated += 1

        try:
            price_inserted = self._insert_price_observation(
                conn, source_product_id, product, extracted_at, self.run_id
            )
            if price_inserted:
                self.stats.prices_inserted += 1
            else:
                self.stats.prices_duplicated += 1
        except ValueError as exc:
            self.stats.errors += 1
            self.stats.error_details.append(str(exc))
            logger.error(
                "Error registrando precio para external_id=%s: %s",
                product.get("product_id"),
                exc,
            )

    def run(self) -> ETLStats:
        logger.info("Iniciando ETL %s desde %s", self.code, self.raw_dir)
        started_at = datetime.now(timezone.utc)
        data, raw_path = self._load_raw()
        products = data["products"]
        self.stats.raw_count = len(products)

        with db.get_connection() as conn:
            supermarket_id = self._get_supermarket_id(conn)
            self.run_id = self._create_run(conn, supermarket_id, started_at, str(raw_path))

            # Sección 31: protección contra ejecuciones con muy pocos productos
            # (scraping roto) — no debe interpretarse como descontinuación masiva.
            promedio_historico = self._average_historical_products(conn, supermarket_id)
            if promedio_historico and len(products) < promedio_historico * MIN_PRODUCTS_RATIO_VS_HISTORY:
                mensaje = (
                    f"RAW sospechosamente pequeño para {self.code}: {len(products)} productos "
                    f"vs promedio histórico {promedio_historico:.0f} "
                    f"(umbral: {MIN_PRODUCTS_RATIO_VS_HISTORY:.0%}). "
                    "Run marcado FAILED, no se aplica ciclo de vida."
                )
                logger.error(mensaje)
                self._finish_run(
                    conn, self.run_id, "FAILED", datetime.now(timezone.utc),
                    products_detected=len(products), errors_count=0,
                )
                raise RawValidationError(mensaje)

            external_ids_vistos: list[str] = []
            for product in products:
                self.stats.processed += 1
                try:
                    with conn:
                        self._process_product(conn, supermarket_id, product)
                    external_id = normalize_str(product.get("product_id"))
                    if external_id:
                        external_ids_vistos.append(external_id)
                except Exception as exc:  # noqa: BLE001 - queremos capturar y seguir
                    self.stats.errors += 1
                    self.stats.error_details.append(str(exc))
                    logger.error(
                        "Error procesando producto external_id=%s: %s",
                        product.get("product_id"),
                        exc,
                    )

            with conn:
                resultado_ciclo_vida = self._apply_lifecycle(
                    conn, supermarket_id, external_ids_vistos
                )

            status = "SUCCESS_WITH_ERRORS" if self.stats.errors else "SUCCESS"
            self._finish_run(
                conn,
                self.run_id,
                status,
                datetime.now(timezone.utc),
                products_detected=self.stats.raw_count,
                categories_detected=self.stats.categories_seen,
                products_new=self.stats.products_inserted,
                products_existing=self.stats.products_updated,
                products_missing=resultado_ciclo_vida["missing"] + resultado_ciclo_vida["discontinued"],
                errors_count=self.stats.errors,
            )

        self.stats.print_report(self.code)
        logger.info(
            "ETL %s finalizado (run_id=%s): procesados=%s insertados=%s actualizados=%s "
            "ausentes=%s descontinuados=%s errores=%s",
            self.code,
            self.run_id,
            self.stats.processed,
            self.stats.products_inserted,
            self.stats.products_updated,
            resultado_ciclo_vida["missing"],
            resultado_ciclo_vida["discontinued"],
            self.stats.errors,
        )
        return self.stats
