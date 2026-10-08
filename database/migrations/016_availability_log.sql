-- Disponibilidad por producto y día, para análisis (cuánto se agota cada tienda).
-- Es una tabla APARTE de price_observations a propósito: la app lee precios de
-- price_observations y aquí nunca hay precios, así que un producto agotado no
-- puede colarse como "$0" ni afectar promedios, historial ni "menor precio".
CREATE TABLE IF NOT EXISTS availability_log (
    source_product_id INTEGER NOT NULL REFERENCES source_products(id) ON DELETE CASCADE,
    observed_on       DATE NOT NULL,                 -- día en hora de Bogotá
    available         BOOLEAN NOT NULL,
    reason            TEXT,                          -- sin_precio | precio_no_comparable | NULL si disponible
    scraper_run_id    INTEGER,
    observed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (source_product_id, observed_on)
);

CREATE INDEX IF NOT EXISTS idx_availability_log_day ON availability_log (observed_on, available);
