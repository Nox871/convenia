-- Búsqueda tolerante a errores (voz, OCR, o texto mal escrito): permite
-- encontrar productos por similitud de texto, no solo por coincidencia
-- exacta de substring.
--
-- unaccent: quita tildes antes de comparar palabras ("aromática" no debe
-- partirse en "arom"/"tica" por la tilde al separar palabras).
-- fuzzystrmatch: da `levenshtein()`, la distancia de edición entre dos
-- palabras -- más precisa que la similitud de trigramas para errores de
-- tipeo en palabras cortas (ver app/repositories/product_repository.py:
-- search_products_fuzzy).
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
