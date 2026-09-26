-- Establecimientos físicos. La API ya expone /api/v1/stores; esta tabla
-- sigue vacía hasta que se cargue un proceso real de datos de tiendas.
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
