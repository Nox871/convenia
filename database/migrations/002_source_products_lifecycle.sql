-- Ciclo de vida de producto.
--
-- IMPORTANTE: acoplado a un cambio obligatorio en etl/core.py
-- (_upsert_source_product) que debe dejar de escribir la columna is_active
-- explícitamente (INSERT y ON CONFLICT ... SET) porque pasa a ser una
-- columna GENERADA. Si ese cambio de código no se aplica en el mismo
-- despliegue que esta migración, el ETL falla en el primer INSERT
-- (Postgres prohíbe escribir en columnas GENERATED).
ALTER TABLE source_products
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'TEMPORARILY_UNAVAILABLE', 'DISCONTINUED')),
    ADD COLUMN IF NOT EXISTS consecutive_missing_runs INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS discontinued_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_price_at TIMESTAMPTZ;

-- Backfill defensivo: si alguna fila ya tenía is_active = FALSE (no debería
-- haber ninguna hoy, pero se cubre por si acaso antes de convertir la
-- columna en generada).
UPDATE source_products SET status = 'DISCONTINUED'
WHERE is_active = FALSE AND status = 'ACTIVE';

-- is_active pasa a ser una columna GENERADA a partir de status, para que
-- backend/app/repositories/product_repository.py (que hoy hace
-- `WHERE sp.is_active = TRUE` en dos queries) siga funcionando SIN cambiar
-- una sola línea. Es el único DROP de esta fase de migraciones: la
-- alternativa (mantener is_active manual en paralelo a status) es
-- exactamente la fuente del bug que se corrige (is_active nunca se ponía
-- en FALSE en el código existente).
ALTER TABLE source_products DROP COLUMN IF EXISTS is_active;
ALTER TABLE source_products
    ADD COLUMN is_active BOOLEAN GENERATED ALWAYS AS (status = 'ACTIVE') STORED;

CREATE INDEX IF NOT EXISTS idx_source_products_status ON source_products (status);
