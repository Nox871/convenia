-- Registro de cada ejecución de scraper/ETL por supermercado.
CREATE TABLE IF NOT EXISTS scraper_runs (
    id SERIAL PRIMARY KEY,
    supermarket_id INTEGER NOT NULL REFERENCES supermarkets(id),
    started_at TIMESTAMPTZ NOT NULL,
    finished_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'RUNNING'
        CHECK (status IN ('RUNNING', 'SUCCESS', 'SUCCESS_WITH_ERRORS', 'FAILED')),
    products_detected INTEGER,
    categories_detected INTEGER,
    products_new INTEGER,
    products_existing INTEGER,
    products_missing INTEGER,
    errors_count INTEGER NOT NULL DEFAULT 0,
    scraper_version TEXT,
    raw_location TEXT,
    raw_hash TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_scraper_runs_supermarket
    ON scraper_runs (supermarket_id, started_at DESC);

-- FAILED: el run no cumplió el mínimo de calidad -> no se aplica ciclo de vida.
-- SUCCESS_WITH_ERRORS: hubo errores puntuales en productos individuales pero el run
-- es válido y sí aplica ciclo de vida.
