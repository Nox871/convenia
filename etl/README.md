# ETL + Homologación

`RAW → ETL → source_products/price_observations → homologación →
products/product_matches`

## Ciclo de vida y ejecuciones

Cada corrida de `etl.etl_<código>`:

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

## Estado actual de los datos

D1, Éxito y Carulla ya tienen datos reales cargados; Jumbo y Olímpica
tienen su conector implementado (`scraper/connectors/jumbo`,
`scraper/connectors/olimpica`) pero todavía no se han ejecutado en este
ambiente:

| Tabla | D1 | Éxito | Carulla | Jumbo | Olímpica |
|---|---|---|---|---|---|
| `source_products` | 208 | 1386 | 1026 | 0 | 0 |

`products` (canónico) tiene 556 filas y `product_matches` 1117 (1028
`CONFIRMED`, 89 `REVIEW`), generadas al correr la homologación sobre los
tres supermercados con datos. Ese número crecerá cada vez que se vuelva a
correr `etl.homologacion.run` después de cargar más datos (incluidos
Jumbo y Olímpica cuando se ejecuten).

## Cómo ejecutar

Con el venv del scraper (tiene `psycopg2`/`python-dotenv`), desde
`E:\convenia`:

```bash
# 1. ETL (requiere haber corrido antes el scraper correspondiente)
scraper/.venv/Scripts/python.exe -m etl.etl_d1
scraper/.venv/Scripts/python.exe -m etl.etl_exito
scraper/.venv/Scripts/python.exe -m etl.etl_carulla
scraper/.venv/Scripts/python.exe -m etl.etl_jumbo
scraper/.venv/Scripts/python.exe -m etl.etl_olimpica
# o todos:
scraper/.venv/Scripts/python.exe -m etl.run_etl ALL

# 2. Homologación (usa los source_products de todos los supermercados con datos)
scraper/.venv/Scripts/python.exe -m etl.homologacion.run
```

Ambos pasos son idempotentes: se pueden ejecutar varias veces sin duplicar
categorías, productos, precios ni matches (ver `etl/core.py` y
`etl/homologacion/README.md` para el detalle de cómo se garantiza).

## Módulos

- `etl/etl_d1.py`, `etl/etl_exito.py`, `etl/etl_carulla.py`,
  `etl/etl_jumbo.py`, `etl/etl_olimpica.py`, `etl/run_etl.py` — carga de
  RAW a `source_products`/`price_observations`, compartiendo la misma
  lógica de `etl/core.py`.
- `etl/homologacion/` — módulo independiente del ETL. Ver su propio
  `README.md` para el diseño completo: normalización, señales de
  comparación, umbrales `CONFIRMED`/`REVIEW`, por qué no genera
  `REJECTED` en masa, e idempotencia.

## Verificado

- Cada `etl.etl_<código>` corrido más de una vez sobre el mismo RAW: la
  segunda corrida no inserta duplicados ni genera observaciones de precio
  repetidas (idempotencia confirmada).
- `etl.homologacion.matcher` probado con casos representativos: mismo
  producto/marca/cantidad → `CONFIRMED`; mismo nombre pero marca distinta
  → descartado; productos frescos sin marca con nombre o cantidad
  distintos → descartado.
- `etl.homologacion.run` corrido contra los datos reales de D1, Éxito y
  Carulla: 0 grupos que mezclen dos `source_products` del mismo
  supermercado (verificable con `python -m etl.homologacion.verificar_grupos`).
