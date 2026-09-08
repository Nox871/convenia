-- Vincula cada observación de precio a la ejecución que la originó (RF-PRICE-002,
-- RN-016) y agrega un constraint único real que reemplaza el WHERE NOT EXISTS
-- aplicativo (ERS §29).
ALTER TABLE price_observations
    ADD COLUMN IF NOT EXISTS scraper_run_id INTEGER REFERENCES scraper_runs(id);
-- NULLABLE a propósito: las filas históricas ya existentes no tienen un run
-- asociado y no se puede backfillear un run que nunca existió.

-- Un scraper_run produce como mucho UNA observación por producto: la clave de
-- unicidad real es (source_product_id, scraper_run_id), sin depender de la
-- precisión del timestamp observed_at ni de comparar corridas distintas.
CREATE UNIQUE INDEX IF NOT EXISTS uq_price_observations_run
    ON price_observations (source_product_id, scraper_run_id)
    WHERE scraper_run_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_price_observations_source_product_observed
    ON price_observations (source_product_id, observed_at DESC);
