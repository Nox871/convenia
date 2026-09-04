# Homologación

Paso **posterior e independiente** al ETL. Lee `source_products` (ya
cargados por `etl.etl_d1` / `etl.etl_exito`) y decide qué pares D1↔Éxito
representan el mismo producto, generando `products` (canónico) y
`product_matches` (la relación).

## Ejecutar

```bash
python -m etl.homologacion.run
```

Requiere haber corrido el ETL de D1 y Éxito antes (necesita `source_products`
pobladas). No modifica `source_products` ni `price_observations`.

## Señales usadas

1. **Marca normalizada** — si ambos lados tienen marca y coincide, suma
   puntaje fuerte; si ambos la tienen y NO coincide, resta fuerte (ej.
   "Arroz Diana" vs "Arroz Roa" nunca homologa aunque el nombre se parezca).
   Si falta en algún lado (común en frutas/verduras), no penaliza ni suma:
   simplemente no es una señal disponible.
2. **Similitud de nombre base** — nombre normalizado sin marca ni
   cantidad, comparado con una mezcla de `difflib.SequenceMatcher` y
   solapamiento de palabras (Jaccard).
3. **Cantidad/unidad normalizada** — extrae número+unidad del nombre (ej.
   "500 G", "1 Kg", "180g", "X6") y lo lleva a una unidad base por
   dimensión (peso→gramos, volumen→mililitros, conteo→unidades) para poder
   comparar "1 Kg" con "1000 G". Cantidades incompatibles son señal de que
   son tamaños/SKUs distintos, no el mismo producto.

No se usa código de barras: ni D1 ni Éxito lo exponen en el RAW actual, y
`source_products` no tiene esa columna. El código está preparado para
usarlo si algún día aparece (`products.barcode` ya existe en el esquema),
simplemente hoy no hay señal real que aprovechar — no se inventa.

## Bucket de categoría (para no comparar todo contra todo)

Antes de comparar nombres, cada `source_product` se agrupa por la palabra
clave de canasta familiar que hizo relevante su categoría (`arroz`,
`lacte`, `carne`, `verdur`, ...), usando el mismo clasificador del scraper
(`scraper/core/category_filter.obtener_bucket`). Solo se comparan
candidatos dentro del mismo bucket. Esto evita, por ejemplo, comparar un
lácteo de D1 contra una verdura de Éxito, y reduce drásticamente el número
de comparaciones.

## Umbrales y clasificación

| score           | resultado   |
|-----------------|-------------|
| ≥ 0.80 (y nombre ≥ 0.55) | `CONFIRMED` |
| ≥ 0.55          | `REVIEW`    |
| < 0.55          | se descarta (no se crea ninguna fila) |

Los umbrales son deliberadamente conservadores: es preferible dejar un par
en `REVIEW` (o no crearlo) que fusionar dos productos distintos bajo el
mismo `products.id`.

## Por qué no se generan filas `REJECTED` en masa

`product_matches.product_id` es `NOT NULL`: toda fila, incluso una
rechazada, tiene que apuntar a un producto canónico real. Generar un
`REJECTED` por cada par de productos que NO coincide implicaría comparar
(y fabricar un `products` para) prácticamente cada combinación D1×Éxito
dentro de un bucket — ruido combinatorio sin valor, y en la práctica
"inventar" productos canónicos solo para marcar que no sirven.

`REJECTED` queda reservado, en el esquema, para cuando una fila que sí
llegó a `REVIEW` se descarta explícitamente después (revisión manual, o
una futura corrida con mejor señal que la reclasifica). Esta primera
versión no incluye ese flujo de revisión — es el siguiente paso natural.

## Idempotencia

Solo se consideran `source_products` que **todavía no tienen fila en
`product_matches`** (`NOT EXISTS`). Por lo tanto:

- Reprocesar sin datos nuevos no hace nada (0 candidatos sin resolver).
- Un producto ya emparejado nunca se vuelve a comparar ni se duplica
  (`product_matches.source_product_id` es `UNIQUE`).
- Cada par nuevo homologado crea exactamente un `products` y dos
  `product_matches` (uno por lado), nunca más.

## Limitación conocida (no resuelta en esta versión)

Esta primera versión compara "`source_products` de D1 sin resolver" contra
"`source_products` de Éxito sin resolver" **de la misma corrida**. Si en el
futuro llega un producto nuevo de D1 cuyo equivalente en Éxito **ya** fue
homologado en una corrida anterior, esta versión no lo intentará enlazar al
`products.id` ya existente (ese candidato de Éxito ya no cuenta como "sin
resolver"). La extensión natural es comparar también contra los `products`
ya creados (usando su propio nombre/marca/cantidad) — no se implementó
todavía para no construir esa capa antes de tener datos reales que
confirmen cuántas coincidencias hay siquiera.

## Frutas y verduras

No se asume marca ni código de barras. La comparación se apoya
completamente en nombre base + cantidad/unidad + bucket de categoría. Por
diseño, dos productos frescos con nombres o tamaños distintos (ej. "Tomate
Cherry 250g" vs "Tomate Chonto 1000g") no se homologan — son, en la
práctica, variedades/tamaños distintos y no se debe forzar la coincidencia.
