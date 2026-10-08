-- Código de barras (EAN/GTIN de 14 dígitos, ya validado) de cada producto de
-- supermercado. Permite homologar entre tiendas por identidad exacta del
-- artículo en vez de comparar nombres. Nulo cuando la tienda no lo publica o
-- no es un código de fabricante.
ALTER TABLE source_products ADD COLUMN IF NOT EXISTS ean VARCHAR(14);

CREATE INDEX IF NOT EXISTS idx_source_products_ean
    ON source_products (ean) WHERE ean IS NOT NULL;
