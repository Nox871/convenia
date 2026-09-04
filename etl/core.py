"""Motor genérico de ETL: RAW (D1 / Éxito) -> PostgreSQL.

Ambos scrapers producen RAW con la misma forma de producto (product_id, product_name,
brand, category_id/category, price, list_price, payment_methods, extracted_at, ...),
así que la lógica de carga se comparte por completo; lo único específico por
supermercado es el código (`code`) y la ruta del archivo RAW.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path

from psycopg2.extras import Json

from etl import db
from etl.common import (
    ETLStats,
    normalize_payment_methods,
    normalize_str,
    parse_timestamp,
    slugify,
    to_decimal,
)

logger = logging.getLogger("etl")


class RawValidationError(Exception):
    pass


class SupermarketETL:
    def __init__(self, code: str, raw_path: Path):
        self.code = code
        self.raw_path = Path(raw_path)
        self.stats = ETLStats()
        self._category_cache: dict[str, int] = {}

    # ------------------------------------------------------------------ #
    # Carga y validación del RAW
    # ------------------------------------------------------------------ #
    def _load_raw(self) -> dict:
        if not self.raw_path.exists():
            raise RawValidationError(f"No existe el archivo RAW: {self.raw_path}")

        with open(self.raw_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        if not isinstance(data, dict) or "products" not in data:
            raise RawValidationError(
                f"El RAW de {self.code} no tiene la forma esperada (falta 'products')"
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

        return data

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
                    first_seen_at, last_seen_at, is_active, raw_data
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, TRUE, %s
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
                    is_active = TRUE,
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
                                   observed_at) -> bool:
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
                    observed_at, payment_methods
                )
                SELECT %s, %s, %s, %s, TRUE, %s, %s
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
                    source_product_id,
                    observed_at,
                ),
            )
            row = cur.fetchone()

        return row is not None

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
                conn, source_product_id, product, extracted_at
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
        logger.info("Iniciando ETL %s desde %s", self.code, self.raw_path)
        data = self._load_raw()
        products = data["products"]
        self.stats.raw_count = len(products)

        with db.get_connection() as conn:
            supermarket_id = self._get_supermarket_id(conn)

            for product in products:
                self.stats.processed += 1
                try:
                    with conn:
                        self._process_product(conn, supermarket_id, product)
                except Exception as exc:  # noqa: BLE001 - queremos capturar y seguir
                    self.stats.errors += 1
                    self.stats.error_details.append(str(exc))
                    logger.error(
                        "Error procesando producto external_id=%s: %s",
                        product.get("product_id"),
                        exc,
                    )

        self.stats.print_report(self.code)
        logger.info(
            "ETL %s finalizado: procesados=%s insertados=%s actualizados=%s errores=%s",
            self.code,
            self.stats.processed,
            self.stats.products_inserted,
            self.stats.products_updated,
            self.stats.errors,
        )
        return self.stats
