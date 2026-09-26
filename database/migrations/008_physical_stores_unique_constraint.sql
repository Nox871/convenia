-- La tabla physical_stores quedó sin la restricción UNIQUE(supermarket_id,
-- external_id) que 004_physical_stores.sql ya declaraba -- se agrega aquí
-- en vez de editar esa migración ya aplicada. La necesita el upsert de
-- etl/load_physical_stores.py para no duplicar una tienda si se vuelve a
-- ejecutar la carga.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'physical_stores_supermarket_external_key'
    ) THEN
        ALTER TABLE physical_stores
            ADD CONSTRAINT physical_stores_supermarket_external_key
            UNIQUE (supermarket_id, external_id);
    END IF;
END $$;
