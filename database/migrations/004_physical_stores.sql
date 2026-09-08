-- Establecimientos físicos (ERS §17, §26.8). Schema listo para P1; sin endpoints
-- todavía.
CREATE TABLE IF NOT EXISTS physical_stores (
    id BIGSERIAL PRIMARY KEY,
    supermarket_id INTEGER NOT NULL REFERENCES supermarkets(id),
    external_id TEXT,
    name TEXT NOT NULL,
    address TEXT,
    city TEXT,
    latitude NUMERIC(9, 6),
    longitude NUMERIC(9, 6),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (supermarket_id, external_id)
);
