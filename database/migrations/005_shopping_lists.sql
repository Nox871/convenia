-- Listas de compra (ERS §16, §26.9). Schema listo para P1; sin endpoints todavía.
--
-- Sin sistema de autenticación hoy: owner_ref identifica al dueño de la lista
-- mediante un id de dispositivo generado por la app móvil (no un FK a una
-- tabla de usuarios que no existe). Migrable a FK real si más adelante hay
-- login.
CREATE TABLE IF NOT EXISTS shopping_lists (
    id SERIAL PRIMARY KEY,
    owner_ref TEXT NOT NULL,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shopping_lists_owner ON shopping_lists (owner_ref);

CREATE TABLE IF NOT EXISTS shopping_list_items (
    id SERIAL PRIMARY KEY,
    shopping_list_id INTEGER NOT NULL REFERENCES shopping_lists(id) ON DELETE CASCADE,
    -- Referencia flexible: un producto canónico homologado o, si todavía no
    -- existe homologación para ese ítem, un source_product suelto. Exactamente
    -- uno de los dos debe estar presente (nunca ambos, nunca ninguno).
    product_id INTEGER REFERENCES products(id),
    source_product_id INTEGER REFERENCES source_products(id),
    quantity INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_shopping_list_item_ref CHECK (
        (product_id IS NOT NULL)::int + (source_product_id IS NOT NULL)::int = 1
    )
);

CREATE INDEX IF NOT EXISTS idx_shopping_list_items_list
    ON shopping_list_items (shopping_list_id);
