# ETL + Homologación

`RAW → ETL → source_products/price_observations → homologación →
products/product_matches`

## Ciclo de vida y ejecuciones (ERS v2.0)

Cada corrida de `etl.etl_<código>` ahora:

- Registra un `scraper_runs` (id, inicio/fin, estado, conteos) — ver
  `etl/core.py: _create_run/_finish_run`.
- Lee el RAW más reciente de `data/raw/<supermercado>/productos/` (snapshots
  con timestamp, nunca sobrescritos — ver `scraper/core/raw_writer.py`), no
  un archivo fijo.
- Aplica ciclo de vida de producto: `ACTIVE` → `TEMPORARILY_UNAVAILABLE` (si
  deja de aparecer) → `DISCONTINUED` (tras `PRODUCT_DISCONTINUATION_THRESHOLD_DAYS`,
  default 30, configurable por `.env`) → reactivación a `ACTIVE` si reaparece,
  sin perder su historial de precios.
- Se protege contra RAW sospechosamente pequeños (`MIN_PRODUCTS_RATIO_VS_HISTORY`,
  default 50% del promedio de los últimos runs exitosos): el run se marca
  `FAILED` y NO se aplica ciclo de vida (nunca se descontinúa en masa por un
  scraping roto).

La homologación (`etl/homologacion/run.py`) además intenta enlazar cada
producto nuevo contra los `products` canónicos YA EXISTENTES del mismo
bucket antes de compararlo con otros no resueltos, así que un producto
homologado en una corrida anterior no genera un canónico duplicado cuando
aparece su par en otro supermercado más adelante.

## Estado actual (pendiente de ejecución manual)

> **Ningún proceso de ETL ni de homologación se deja corriendo ni se
> programa automáticamente.** Esta etapa quedó con el código implementado,
> compilando y probado con datos sintéticos/parciales; la ejecución sobre
> el volumen completo de datos reales (una vez el scraping de Éxito se
> corra manualmente) queda a cargo de quien opere el proyecto.

Estado real de la base de datos al día de hoy:

| Tabla | D1 | Éxito | Total |
|---|---|---|---|
| `source_categories` | 7 | 0 | 7 |
| `source_products` | 206 | 0 | 206 |
| `price_observations` | 276 | 0 | 276 |
| `products` | — | — | 0 |
| `product_matches` | — | — | 0 |

`products`/`product_matches` siguen en 0 porque Éxito todavía no tiene
`source_products` cargados (su scraping está pendiente de ejecución
manual, ver `scraper/README.md`) — la homologación necesita datos de
**ambos** supermercados para poder cruzar algo. Correrla hoy contra solo
D1 no generaría ningún match real.

## Cómo ejecutar (manual, cuando corresponda)

Con el venv del scraper (tiene `psycopg2`/`python-dotenv`), desde
`E:\convenia`:

```bash
# 1. ETL (requiere haber corrido antes los scrapers correspondientes)
scraper/.venv/Scripts/python.exe -m etl.etl_d1
scraper/.venv/Scripts/python.exe -m etl.etl_exito
# o ambos:
scraper/.venv/Scripts/python.exe -m etl.run_etl ALL

# 2. Homologación (requiere source_products de D1 Y Éxito)
scraper/.venv/Scripts/python.exe -m etl.homologacion.run
```

Ambos pasos son idempotentes: se pueden ejecutar varias veces sin duplicar
categorías, productos, precios ni matches (ver `etl/core.py` y
`etl/homologacion/README.md` para el detalle de cómo se garantiza).

## Módulos

- `etl/etl_d1.py`, `etl/etl_exito.py`, `etl/run_etl.py` — carga de RAW a
  `source_products`/`price_observations`. Sin cambios de lógica en esta
  etapa de homologación (solo se usaron para cargar los datos de D1 ya
  filtrados a canasta familiar).
- `etl/homologacion/` — módulo nuevo e independiente. Ver su propio
  `README.md` para el diseño completo: normalización, señales de
  comparación, umbrales `CONFIRMED`/`REVIEW`, por qué no genera
  `REJECTED` en masa, e idempotencia.

## Validado (sin ejecutar contra el dataset completo)

- `etl.etl_d1` corrido dos veces sobre el mismo RAW: segunda corrida =
  0 insertados, 0 categorías nuevas, todos los precios detectados como
  duplicados (idempotencia confirmada).
- `etl.homologacion.matcher` probado con casos sintéticos representativos:
  mismo producto/marca/cantidad → `CONFIRMED`; mismo nombre pero marca
  distinta → descartado; productos frescos sin marca con nombre o
  cantidad distintos → descartado. No se ejecutó todavía sobre el
  dataset real completo (falta Éxito).
