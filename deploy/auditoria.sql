-- Auditoría de coherencia de datos de Convenia. SOLO LECTURA (ningún UPDATE/DELETE).
-- Uso:  psql -h localhost -U $DB_USER $DB_NAME -f deploy/auditoria.sql
-- Cada bloque debería dar 0 filas / 0 en "problemas" salvo que se indique lo contrario.

\echo
\echo '=== 1. Productos por supermercado y estado ==='
SELECT s.code, sp.status, count(*) AS productos
FROM source_products sp JOIN supermarkets s ON s.id = sp.supermarket_id
GROUP BY 1, 2 ORDER BY 1, 2;

\echo
\echo '=== 2. Precios <= 0 guardados (debe ser 0) ==='
SELECT count(*) AS problemas FROM price_observations WHERE price <= 0;

\echo
\echo '=== 3. Más de una observación por producto y por día (debe ser 0) ==='
SELECT count(*) AS problemas FROM (
  SELECT source_product_id, (observed_at AT TIME ZONE 'America/Bogota')::date AS dia
  FROM price_observations GROUP BY 1, 2 HAVING count(*) > 1) t;

\echo
\echo '=== 4. Observaciones por día (la carga diaria debe verse un punto por tienda y día) ==='
SELECT (po.observed_at AT TIME ZONE 'America/Bogota')::date AS dia, s.code, count(*) AS observaciones
FROM price_observations po
JOIN source_products sp ON sp.id = po.source_product_id
JOIN supermarkets s ON s.id = sp.supermarket_id
GROUP BY 1, 2 ORDER BY 1 DESC, 2 LIMIT 25;

\echo
\echo '=== 5. Productos ACTIVE sin ninguna observación de precio (debe ser 0) ==='
SELECT s.code, count(*) AS problemas
FROM source_products sp JOIN supermarkets s ON s.id = sp.supermarket_id
WHERE sp.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM price_observations po WHERE po.source_product_id = sp.id)
GROUP BY 1;

\echo
\echo '=== 6. Productos ACTIVE cuyo último precio tiene más de 3 días (precio viejo mostrado como actual) ==='
SELECT s.code, count(*) AS problemas
FROM source_products sp JOIN supermarkets s ON s.id = sp.supermarket_id
WHERE sp.status = 'ACTIVE' AND sp.last_price_at < now() - interval '3 days'
GROUP BY 1;

\echo
\echo '=== 7. Precios sospechosos (< $200 o > $1.500.000), con ejemplo ==='
SELECT s.code, sp.name_raw, po.price
FROM price_observations po
JOIN source_products sp ON sp.id = po.source_product_id
JOIN supermarkets s ON s.id = sp.supermarket_id
WHERE (po.price < 200 OR po.price > 1500000)
ORDER BY po.price DESC LIMIT 15;

\echo
\echo '=== 8. Precio de lista menor que el precio (descuento al revés) ==='
SELECT count(*) AS problemas FROM price_observations
WHERE list_price IS NOT NULL AND list_price > 0 AND list_price < price;

\echo
\echo '=== 9. Mismo supermercado y mismo nombre con distinto id (posible duplicado) ==='
SELECT s.code, count(*) AS grupos_duplicados FROM (
  SELECT supermarket_id, lower(name_raw) AS n FROM source_products
  WHERE status = 'ACTIVE' GROUP BY 1, 2 HAVING count(*) > 1) d
JOIN supermarkets s ON s.id = d.supermarket_id GROUP BY 1;

\echo
\echo '=== 10. Homologación: productos canónicos según cuántos supermercados cubren ==='
SELECT tiendas, count(*) AS canonicos FROM (
  SELECT pm.product_id, count(DISTINCT sp.supermarket_id) AS tiendas
  FROM product_matches pm JOIN source_products sp ON sp.id = pm.source_product_id
  WHERE pm.status = 'CONFIRMED' GROUP BY 1) t
GROUP BY 1 ORDER BY 1;

\echo
\echo '=== 11. Canónicos con 2+ productos DEL MISMO supermercado (debería ser casi 0) ==='
SELECT count(*) AS problemas FROM (
  SELECT pm.product_id, sp.supermarket_id
  FROM product_matches pm JOIN source_products sp ON sp.id = pm.source_product_id
  WHERE pm.status = 'CONFIRMED' GROUP BY 1, 2 HAVING count(*) > 1) t;

\echo
\echo '=== 12. Productos activos SIN match confirmado, por supermercado (se listan sueltos) ==='
SELECT s.code, count(*) AS sueltos
FROM source_products sp JOIN supermarkets s ON s.id = sp.supermarket_id
WHERE sp.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM product_matches pm
                  WHERE pm.source_product_id = sp.id AND pm.status = 'CONFIRMED')
GROUP BY 1 ORDER BY 1;

\echo
\echo '=== 13. Matches confirmados entre productos de DISTINTA marca (debe ser 0) ==='
SELECT count(*) AS problemas FROM (
  SELECT pm.product_id
  FROM product_matches pm JOIN source_products sp ON sp.id = pm.source_product_id
  WHERE pm.status = 'CONFIRMED' AND sp.brand_raw IS NOT NULL AND btrim(sp.brand_raw) <> ''
  GROUP BY 1 HAVING count(DISTINCT lower(btrim(sp.brand_raw))) > 1) t;

\echo
\echo '=== 14. Ejemplos de matches confirmados con marca distinta (revisar a ojo) ==='
SELECT pm.product_id, string_agg(DISTINCT s.code || ': ' || sp.name_raw, ' | ') AS productos
FROM product_matches pm
JOIN source_products sp ON sp.id = pm.source_product_id
JOIN supermarkets s ON s.id = sp.supermarket_id
WHERE pm.status = 'CONFIRMED' AND sp.brand_raw IS NOT NULL AND btrim(sp.brand_raw) <> ''
GROUP BY 1 HAVING count(DISTINCT lower(btrim(sp.brand_raw))) > 1
LIMIT 8;

\echo
\echo '=== 15. Productos sin marca, por supermercado ==='
SELECT s.code, count(*) FILTER (WHERE sp.brand_raw IS NULL OR btrim(sp.brand_raw) = '') AS sin_marca, count(*) AS total
FROM source_products sp JOIN supermarkets s ON s.id = sp.supermarket_id
WHERE sp.status = 'ACTIVE' GROUP BY 1 ORDER BY 1;

\echo
\echo '=== 16. Tiendas físicas por supermercado (sin coordenadas = no cuentan para el rango) ==='
SELECT s.code, count(*) AS tiendas,
       count(*) FILTER (WHERE ps.latitude IS NULL OR ps.longitude IS NULL) AS sin_coordenadas
FROM physical_stores ps JOIN supermarkets s ON s.id = ps.supermarket_id
GROUP BY 1 ORDER BY 1;

\echo
\echo '=== 17. Últimas corridas de ETL ==='
SELECT sr.id, s.code, sr.started_at, sr.status, sr.products_detected, sr.products_new, sr.products_missing, sr.errors_count
FROM scraper_runs sr JOIN supermarkets s ON s.id = sr.supermarket_id
ORDER BY sr.id DESC LIMIT 10;

\echo
\echo '=== 18. Categorías de producto: nombres que NO parecen canasta (muebles/aparatos) en la base ==='
SELECT s.code, sp.name_raw
FROM source_products sp JOIN supermarkets s ON s.id = sp.supermarket_id
WHERE sp.status = 'ACTIVE'
  AND lower(sp.name_raw) ~ '^(mini |mega )?(mueble|aspiradora|dispensador|batidor|licuadora|cafetera|freidora|ventilador|robot|estufa|nevera|lavadora)'
LIMIT 15;
