-- Presupuesto opcional por lista de compra (pesos colombianos, entero).
-- NULL = la lista no tiene presupuesto definido. Es por lista y no por
-- usuario: cada compra ("Mercado del mes", "Compra de la semana") tiene su
-- propio tope.
ALTER TABLE shopping_lists
    ADD COLUMN IF NOT EXISTS budget BIGINT CHECK (budget IS NULL OR budget >= 0);
