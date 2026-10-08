-- Búsquedas frecuentes de la app ("Leche", "Arroz"...). Se guarda SÓLO el texto
-- buscado y cuántas veces se buscó: ningún dato de la persona, ni dispositivo ni
-- cuenta. Sólo se cuentan búsquedas que dieron resultados, para no llenar la
-- lista de errores de tipeo.
CREATE TABLE IF NOT EXISTS search_terms (
    term             TEXT PRIMARY KEY,            -- clave normalizada (minúsculas, sin tildes)
    display          TEXT NOT NULL,               -- cómo se muestra ("Café")
    searches         INTEGER NOT NULL DEFAULT 0,
    last_searched_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_search_terms_searches ON search_terms (searches DESC);
