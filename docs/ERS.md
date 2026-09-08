# Especificación de Requisitos de Software (ERS) — Convenia

**Producto:** Convenia
**Slogan:** Antes de comprar, elige dónde.
**Versión del documento:** 3.0 (as-built — refleja el sistema realmente implementado, incluye el rediseño de experiencia y sistema visual)
**Fecha:** 2026-09-08
**Plataforma:** Aplicación móvil (Flutter) + API REST (FastAPI) + PostgreSQL
**Fuentes de datos:** D1, Éxito, Carulla, Jumbo, Olímpica

> Este documento describe la especificación tal como está **construida y verificada** en el
> repositorio a la fecha, siguiendo el enfoque de requisitos verificables y trazables de
> ISO/IEC/IEEE 29148. Cada sección indica su estado de implementación. No incluye
> funcionalidad aspiracional sin marcar: lo que se describe como "implementado" fue
> verificado end-to-end (compilación, ejecución real contra la base de datos, o ambas).

---

## 1. Introducción

### 1.1 Propósito

Convenia es un sistema de apoyo a la decisión de compra que permite consultar productos y
comparar sus precios entre cinco supermercados colombianos (D1, Éxito, Carulla, Jumbo,
Olímpica). La información se obtiene mediante scraping automatizado, se transforma con un
proceso ETL, se conserva de forma histórica e inmutable, y se expone mediante una API REST
consumida por una aplicación móvil.

La pregunta central que el sistema resuelve:

> **¿Dónde me conviene comprar este producto?** — y, cuando aplica, **¿dónde me conviene
> comprar toda mi lista?**

### 1.2 Alcance del documento

Cubre: capa de adquisición (scrapers), almacenamiento histórico (RAW + ejecuciones), ETL,
homologación de productos, modelo de datos, API REST, aplicación móvil, requisitos no
funcionales, reglas de negocio, configuración, trazabilidad y estado de verificación.

---

## 2. Objetivo del sistema

Conservar la evolución de la información (no sólo el precio actual) y permitir diferenciar
correctamente:

```
Producto nuevo → Producto activo → Producto temporalmente ausente
→ Producto descontinuado → Producto reactivado
```

manteniendo en todo momento: RAW histórico, ejecuciones (`scraper_runs`), productos de
fuente, homologaciones, observaciones de precio, estado del producto y trazabilidad.

---

## 3. Arquitectura implementada

```
D1 · Éxito · Carulla · Jumbo · Olímpica
            │
            ▼
   Scrapers (crawl4ai, por conector) ──► RAW histórico inmutable
            │                             (data/raw/<supermercado>/productos/
            │                              <code>_raw_<timestamp>.json + latest.json)
            ▼
   ETL (etl/core.py, compartido por los 5)
     • registra scraper_runs
     • upsert idempotente de categorías/productos/precios
     • ciclo de vida: ACTIVE ⇄ TEMPORARILY_UNAVAILABLE → DISCONTINUED ⇄ reactivación
     • protección contra RAW anómalamente pequeño (no descontinúa en masa)
            │
            ▼
   Homologación (etl/homologacion/) ──► products + product_matches
     • cross-run: enlaza contra canónicos existentes antes de crear uno nuevo
     • validación post-grupo: ningún grupo mezcla dos source_products
       del mismo supermercado ni presentaciones/cantidades incompatibles
            │
            ▼
        PostgreSQL (schema versionado en database/migrations/)
            │
            ▼
   Backend FastAPI — /api/v1/*  (SQLAlchemy Core, sin ORM)
            │
            ▼
   App móvil Flutter (Provider) — Inicio · Resultados · Detalle/Comparación
   · Historial · Listas · Establecimientos · Configuración
```

`scraper/`, `etl/` y `backend/` corren en entornos (venv) separados. La única lógica
compartida entre los tres sin duplicarse es el clasificador de categorías, extraído a
`shared/category_filter.py` (sin dependencias externas), del que `scraper/core/category_filter.py`
re-exporta para no romper los imports existentes.

---

## 4. Fuentes de datos

| Código | Supermercado | Categorías | Productos de fuente | Estado del scraper |
|---|---|---|---|---|
| D1 | Tiendas D1 | ✅ | ✅ | Cargado |
| EXITO | Éxito | ✅ | ✅ | Cargado |
| CARULLA | Carulla | ✅ | ✅ | Cargado |
| JUMBO | Jumbo | ✅ | 0 (sin ejecutar) | Conector implementado, sin ejecutar en este ambiente |
| OLIMPICA | Olímpica | ✅ | 0 (sin ejecutar) | Conector implementado, sin ejecutar en este ambiente |

La arquitectura no asume un número fijo de supermercados: `supermarkets` es una tabla, y
tanto la comparación de precios (`/compare`) como el costo de listas (`/lists/{id}/cost`)
iteran dinámicamente sobre los supermercados activos, cualquiera sea su cantidad (ERS §4/§36
del documento original — verificado explícitamente para no hardcodear "5").

---

## 5. Modelo de datos (schema real, versionado)

El schema vive en `database/migrations/` (runner: `database/run_migrations.py`, con tabla de
control `schema_migrations`). Estado real de la base de desarrollo al momento de escribir
este documento:

| Tabla | Filas | Notas |
|---|---|---|
| `supermarkets` | 5 | incluye `website_url`, `currency`, `is_active`, `created_at` |
| `source_categories` | 168 | |
| `source_products` | 2620 | 2618 `ACTIVE`, 2 `DISCONTINUED` (verificado en vivo) |
| `price_observations` | 2894 | vinculadas a `scraper_run_id` |
| `products` (canónico) | 556 | |
| `product_matches` | 1117 | 1028 `CONFIRMED`, 89 `REVIEW`, 0 `REJECTED` (reservado) |
| `scraper_runs` | 5 | una por ejecución de ETL |
| `physical_stores` | 0 | schema listo, sin datos sembrados todavía |
| `shopping_lists` / `shopping_list_items` | 0 | schema listo, se llenan por uso real de la app |

### 5.1 `scraper_runs`

```
id · supermarket_id · started_at · finished_at
status: RUNNING | SUCCESS | SUCCESS_WITH_ERRORS | FAILED
products_detected · categories_detected · products_new · products_existing
· products_missing · errors_count · scraper_version · raw_location · raw_hash · created_at
```

### 5.2 `source_products` (ciclo de vida)

```
... columnas originales ...
status: ACTIVE | TEMPORARILY_UNAVAILABLE | DISCONTINUED
consecutive_missing_runs · discontinued_at · last_price_at
is_active  -- columna GENERADA a partir de status (compatibilidad con el backend existente)
```

### 5.3 `price_observations`

Constraint único real `(source_product_id, scraper_run_id)` — un run produce como mucho una
observación por producto; reemplaza el `WHERE NOT EXISTS` aplicativo previo.

### 5.4 `physical_stores`

```
id · supermarket_id · external_id · name · address · city
· latitude · longitude · is_active · created_at
```

### 5.5 `shopping_lists` / `shopping_list_items`

```
shopping_lists: id · owner_ref · name · created_at · updated_at
shopping_list_items: id · shopping_list_id · product_id (nullable)
  · source_product_id (nullable, exactamente uno de los dos) · quantity · created_at
```

`owner_ref` identifica el dispositivo (sin sistema de autenticación en el proyecto);
migrable a un FK de usuario real si más adelante se agrega login.

---

## 6. Ciclo de vida de producto — RF-LIFE

Implementado en `etl/core.py`. Verificado con datos reales de D1 (ver §17):

- **RF-LIFE-001 (alta):** producto nuevo → `first_seen_at`/`last_seen_at`, `status=ACTIVE`,
  procesado por ETL, precio registrado, intento de homologación independiente.
- **RF-LIFE-002 (actualización):** producto visto de nuevo → `last_seen_at` actualizado,
  `consecutive_missing_runs=0`, `status=ACTIVE` (incluye reactivación desde `DISCONTINUED`).
- **RF-LIFE-003/004 (ausencia):** producto no visto → `status=TEMPORARILY_UNAVAILABLE`,
  `consecutive_missing_runs` se incrementa en **cada** corrida donde sigue ausente (no sólo
  la primera vez).
- **RF-LIFE-005 (descontinuación):** tras `PRODUCT_DISCONTINUATION_THRESHOLD_DAYS` (default
  30, variable de entorno) sin aparecer → `status=DISCONTINUED`, `discontinued_at`.
- **RF-LIFE-006 (reactivación):** producto descontinuado que reaparece → vuelve a `ACTIVE`
  sin perder su historial de precios.
- **RF-LIFE-007:** nunca se elimina físicamente un `source_product` por ausencia.

**Sección 31 (protección contra fallas de scraping):** si un RAW trae menos del
`MIN_PRODUCTS_RATIO_VS_HISTORY` (default 50%) del promedio de los últimos runs exitosos, el
run se marca `FAILED` y **no se aplica ningún cambio de ciclo de vida** — evita
descontinuaciones masivas por un scraper roto.

---

## 7. Historial de precios — RF-PRICE

- Cada observación es un registro independiente, nunca se sobrescribe (RF-PRICE-001).
- Contiene producto de fuente, precio, precio de lista, moneda, disponibilidad, fecha de
  observación, métodos de pago, y la ejecución que la originó (RF-PRICE-002).
- `GET /api/v1/products/{id}/history` expone agregados (mínimo, máximo, promedio, actual,
  variación %) calculados en SQL, y la lista de observaciones **paginada** por separado
  (RNF-PERF-003 — nunca se trae todo el historial de una sola vez).

---

## 8. Homologación de productos — RF-MATCH

Motor en `etl/homologacion/` (`matcher.py`, `run.py`, `normalize.py`):

- Señales: nombre (similitud de texto 55%), marca (±30/35%), cantidad/unidad (±15/20%,
  compatibilidad de dimensión peso/volumen/conteo). No usa código de barras (ninguna fuente
  lo expone hoy); `products.barcode` queda reservado.
- Umbrales `CONFIRM_THRESHOLD=0.80` / `REVIEW_THRESHOLD=0.55`, overrideables por entorno
  (`MATCH_CONFIRM_THRESHOLD`, `MATCH_REVIEW_THRESHOLD`).
- Unión de coincidencias vía Union-Find dentro de cada bucket de categoría.
- **Cross-run:** antes de agrupar candidatos "no resueltos" entre sí, cada uno se intenta
  enlazar contra un `products` canónico **ya existente** del mismo bucket — un producto
  nuevo de un supermercado ya no crea un canónico duplicado si su par en otro supermercado
  fue homologado en una corrida anterior (resuelve la limitación documentada originalmente
  en el propio módulo).
- **Validación de integridad del grupo:** un grupo homologado nunca contiene dos
  `source_products` del mismo supermercado ni presentaciones/cantidades incompatibles bajo
  el mismo canónico (corregido tras detectarse en pruebas reales que el union-find
  transitivo podía fusionar indirectamente productos de un mismo supermercado a través de
  un tercero — verificado: 0 grupos contaminados sobre 556 productos canónicos / 1117
  matches al momento de escribir este documento).
- Estados: `CONFIRMED` / `REVIEW` (ambos se escriben); `PENDING` es la ausencia de fila
  (interpretación intencional); `REJECTED` reservado para un flujo de revisión manual futuro.

---

## 9. Filtrado de categorías — RF-NORM-005

`shared/category_filter.py`: listas de palabras clave de inclusión/exclusión (no una lista
rígida de categorías), normalización de texto (minúsculas, sin acentos, decodificación de
URL), con orden determinista de evaluación (una `tuple`, no un `set`, para que la asignación
de "bucket" no dependa de `PYTHONHASHSEED` entre procesos). Categorías incluidas: alimentos,
bebidas no alcohólicas, frutas/verduras, carnes, pescados, lácteos, huevos, granos, cereales,
despensa, aseo del hogar, cuidado personal. Excluidas: tecnología, electrodomésticos, ropa,
calzado, juguetes, videojuegos, deportes, alcohol, tabaco, salud/farmacia, mascotas, y otros
verticales fuera de canasta familiar.

---

## 10. API REST — `/api/v1/`

Versionada (excepto `/api/health`, sin versión). Documentación OpenAPI automática en
`/docs`. Todos los siguientes endpoints fueron probados con datos reales:

### Sistema
```
GET /api/health
```

### Supermercados
```
GET /api/v1/supermarkets            -- incluye last_successful_run_at (fecha de actualización)
GET /api/v1/supermarkets/{id}
```

### Categorías
```
GET /api/v1/categories              -- normalizadas a "bucket" común, con conteo de productos
```

### Productos
```
GET /api/v1/products                -- búsqueda paginada, tolerante a mayúsc./acentos
                                        ?sort=price|recent (RF-SEARCH-002)
GET /api/v1/products/{id}
```
El listado opera en dos fases combinadas por un mismo `ORDER BY`/`OFFSET`/`LIMIT` (CTE con
`UNION ALL` + `COUNT(*) OVER()`): los `source_products` con un `product_match` `CONFIRMED`
se agrupan bajo su producto canónico (una fila con `offers_count` = número de supermercados
con oferta y el mejor precio entre ellos); los que aún no tienen coincidencia confirmada se
listan sueltos, con `offers_count=1` — **nunca se ocultan** productos por no estar
homologados. `sort=distance` está definido pero deshabilitado en la app mientras
`physical_stores` no tenga datos reales (ver §18).

### Precios
```
GET /api/v1/products/{id}/prices
GET /api/v1/products/{id}/history          -- agregados + observaciones paginadas; ?month=YYYY-MM filtra por mes
GET /api/v1/products/{id}/history/monthly  -- promedio/mínimo/máximo/conteo por mes con dato real (nunca meses rellenados con 0)
```

### Comparación
```
GET /api/v1/products/{id}/compare
```
Devuelve una fila **por cada supermercado activo** (nunca un número fijo), con
`price/currency/observed_at: null` y "Sin datos" cuando no hay oferta (nunca precio 0),
`is_stale` por oferta (umbral `data_freshness_threshold_hours`), `is_partial` a nivel de
respuesta, `savings_absolute`/`savings_percentage` (referencia: precio máximo, documentada
en `savings_reference`), y `unit_price`/`unit_label` ($/kg, $/L, $/unidad) cuando el
producto es canónico y su cantidad/unidad se pudo extraer con confianza.

### Listas de compra
```
GET    /api/v1/lists?owner_ref=...
POST   /api/v1/lists
GET    /api/v1/lists/{id}?owner_ref=...
PUT    /api/v1/lists/{id}?owner_ref=...
DELETE /api/v1/lists/{id}?owner_ref=...
POST   /api/v1/lists/{id}/items
PUT    /api/v1/lists/{id}/items/{item_id}
DELETE /api/v1/lists/{id}/items/{item_id}
GET    /api/v1/lists/{id}/cost
GET    /api/v1/lists/{id}/cost/distributed
```
`owner_ref` (id de dispositivo) protege cada lista: una request con el `owner_ref`
incorrecto recibe 404, no los datos de otro dispositivo. El costo por supermercado sólo
declara "conveniente" al que tiene la lista **completa** (nunca compara un total parcial
contra uno completo, para no sugerir falsamente que el que menos datos tiene es el más
barato). `/cost/distributed` reutiliza la misma matriz ítem×supermercado ya calculada por
`/cost` (sin consultas SQL nuevas) para elegir, por ítem, el supermercado con menor precio y
agrupar el resultado en "paradas" de compra; los ítems sin precio en ningún supermercado se
reportan aparte (`unpriced_item_ids`), nunca se fuerzan a $0. La app sólo ofrece esta
alternativa cuando su total es **estrictamente menor** que el mejor total de una tienda
completa — si no hay ahorro real, no se muestra.

### Establecimientos
```
GET /api/v1/stores?supermarket=...
GET /api/v1/stores/nearby?lat=...&lon=...&radius_km=...   -- incluye walking_minutes
```
Distancia calculada con fórmula de Haversine en SQL; tiempo a pie estimado como
`distance_km / WALKING_SPEED_KMH * 60` (variable de entorno, default 4.5 km/h). Sin datos
sembrados todavía (devuelve lista vacía honesta, no inventada).

### Respuestas y errores

Códigos usados: 200/201/204 éxito, 400 parámetros inválidos, 404 recurso inexistente, 500
error interno no controlado. No se expone información de PostgreSQL, credenciales ni
connection strings en ninguna respuesta de error.

---

## 11. Aplicación móvil (Flutter + Provider)

Shell de navegación con barra inferior: **Inicio · Listas · Tiendas · Config**. Cada
pestaña se construye sólo al visitarse por primera vez (evita llamadas HTTP innecesarias al
arrancar — Inicio sigue siendo la única pantalla sin red hasta que el usuario busca algo).

| Pantalla ERS §23 | Estado |
|---|---|
| Inicio | ✅ — sin indicador fijo de "N vs M" supermercados (se retiró por asumir sólo 2; ver §11.1) |
| Búsqueda / Resultados | ✅ — agrupación real de homologados ("Desde $X en N supermercados"), orden por precio/recencia, panel de filtros avanzados oculto por defecto |
| Detalle + Comparación (una sola pantalla) | ✅ — jerarquía Producto → Precio → Precios registrados/Disponibilidad → Actualidad → Historial → Agregar a lista; categoría en lenguaje natural (nunca la ruta técnica); título "Disponibilidad" (1 oferta) o "Precios registrados" (≥2), nunca "Todas las ofertas"; filas "Sin datos" ocultas cuando sólo hay 0-1 oferta real |
| Historial | ✅ — barras mensuales (altura = promedio del mes) con toque para ver detalle del mes (mín/máx/promedio/observaciones); meses sin dato real nunca se rellenan |
| Listas | ✅ — crear/renombrar/eliminar, agregar productos vía buscador, costo por supermercado con badge de incompletitud prominente, y "Comprar distribuido" cuando conviene |
| Establecimientos | ✅ (UI + geolocalización con timeout — ver §11.1) — sin datos reales de tiendas físicas todavía; tiempo a pie estimado listo para cuando existan |
| Configuración | ✅ — fuente de datos, fecha de actualización por supermercado, info de la app |

La app nunca accede a PostgreSQL directamente; toda comunicación pasa por `ApiClient` →
repositories → controllers → screens.

### 11.1 Correcciones de comportamiento real (detectadas usando la app, no en revisión de código)

- **RF-SEARCH-002 (orden real, sin filtro hardcodeado):** el listado de Resultados usaba un
  filtro fijo de dos supermercados con etiquetas literales ("Mejor en D1"/"Mejor en Éxito"),
  inválido en cuanto se añade un tercer supermercado con datos. Se reemplazó por un control
  de orden (`ResultsSort`: precio, recencia) poblado dinámicamente; "Más cercano" queda
  definido pero deshabilitado con explicación visible mientras no haya ubicaciones reales.
- **RF-STORE-002 (cuelgue de geolocalización):** `Geolocator.getCurrentPosition` se llamaba
  sin límite de tiempo; en un emulador o con mala señal GPS, la espera nunca terminaba y la
  pantalla de Establecimientos quedaba cargando indefinidamente. Se agregó `timeLimit` de la
  propia librería más un `.timeout()` externo y un estado `timedOut` explícito con opción de
  reintentar.

### 11.2 Sistema de diseño visual

Paleta de marca fija (Indigo `#5B4FE9`, Ink `#17171C`, Soft Ivory `#F7F5EF`, Lavender Mist
`#ECEAFF`, y semántica success/warning/error) aplicada mediante tokens `const Color` en
`core/theme.dart`, con tipografía Manrope (títulos/precios) e Inter (cuerpo/metadatos) vía
`google_fonts`. Los supermercados **no** tienen color propio — se distinguen únicamente por
nombre — para no sesgar visualmente la comparación hacia ningún establecimiento. Detalle
completo (principios, jerarquía por pantalla, reglas de proporción) en `docs/UI-UX.md`.

---

## 12. Requisitos no funcionales

- **Seguridad:** credenciales fuera del código fuente (`.env`, no versionado; `.env.example`
  documenta las variables). Consultas parametrizadas (SQLAlchemy `text()` con bind params /
  psycopg2 `%s`) en todo el proyecto — sin concatenación de SQL.
- **Rendimiento:** historial paginado en backend (nunca se trae todo de una vez); umbral de
  frescura de datos resuelto una sola vez en memoria del proceso, no por request.
- **Escalabilidad:** `/compare` y el costo de listas iteran sobre `supermarkets` activos sin
  asumir cantidad fija; agregar un supermercado nuevo no requiere tocar el motor de
  comparación ni el modelo canónico.
- **Observabilidad:** cada ejecución de ETL queda registrada en `scraper_runs` con
  conteos completos; logs con nivel/formato estándar, sin credenciales.
- **Mantenibilidad:** umbrales de negocio (días de descontinuación, confianza de match,
  ratio mínimo de calidad, frescura de datos) son variables de entorno, no constantes en el
  código — cambiarlos no requiere modificar la arquitectura.

---

## 13. Configuración (variables de entorno)

Documentadas en `.env.example`:

```
DB_HOST · DB_PORT · DB_NAME · DB_USER · DB_PASSWORD
BACKEND_CORS_ORIGINS · DATA_FRESHNESS_THRESHOLD_HOURS
PRODUCT_DISCONTINUATION_THRESHOLD_DAYS · MIN_PRODUCTS_RATIO_VS_HISTORY
MATCH_CONFIRM_THRESHOLD · MATCH_REVIEW_THRESHOLD
```

---

## 14. Reglas de negocio verificadas

| Regla | Estado |
|---|---|
| RN-001 Un precio nuevo no reemplaza uno histórico | ✅ (constraint único por run) |
| RN-003 Ausencia ≠ descontinuación inmediata | ✅ (`TEMPORARILY_UNAVAILABLE` intermedio) |
| RN-004 Run fallido no genera descontinuaciones | ✅ (chequeo de calidad mínima) |
| RN-005/006 Descontinuado/reactivado conserva historial | ✅ (verificado con `PRODUCT_DISCONTINUATION_THRESHOLD_DAYS=0`) |
| RN-007 Sin equivalente no se homologa artificialmente | ✅ (grupo <2 miembros no crea canónico) |
| RN-008 Comparabilidad real (no sólo nombre) | ✅ (marca + cantidad en el scoring; validación post-grupo) |
| RN-009 Sin datos ≠ precio 0 | ✅ (`null` explícito en `/compare`) |
| RN-016 Observación ligada a su ejecución | ✅ (`scraper_run_id`) |
| RN-019 Mejor precio sólo con observaciones válidas | ✅ (`available=TRUE`, no stale-agnostic) |

---

## 15. Trazabilidad

```
Precio mostrado → price_observation → source_product → supermarket
→ scraper_run → RAW snapshot (data/raw/<supermercado>/productos/<code>_raw_<timestamp>.json)
```
```
Producto canónico → product_match → source_product → supermarket → RAW
```
Ambas cadenas son reconstruibles: cada `price_observations` referencia su `scraper_run_id`,
cada `scraper_runs` referencia `raw_location`/`raw_hash`.

---

## 16. Pruebas y verificación realizadas

No existen suites de test automatizadas de backend/ETL todavía (`backend/tests` no existe);
la verificación de esta fase se hizo por ejecución real dirigida:

- Migraciones aplicadas dos veces sin duplicar (`schema_migrations` las omite).
- ETL D1 corrido 3 veces seguidas: idempotencia de precios/productos confirmada;
  detección de ausentes, incremento de `consecutive_missing_runs` en corridas sucesivas,
  descontinuación forzando el umbral a 0 días, todo verificado contra la base real.
  ETL Éxito corrido como smoke test adicional (1386 productos, 0 errores).
- Homologación corrida contra datos reales de 3 supermercados: cross-run enlazó 6
  productos nuevos contra canónicos preexistentes sin duplicar; validación post-grupo
  confirmada con 0 contaminaciones sobre 556 canónicos / 1117 matches.
- Backend probado end-to-end con `curl` real: todos los endpoints de esta sección 10,
  incluyendo CRUD completo de listas (crear, agregar ítems mixtos canónico+suelto, costo,
  renombrar, eliminar, protección por `owner_ref`).
- Mobile: `flutter analyze` sin issues, `flutter test` (smoke test de Inicio) en verde tras
  cada cambio.

Pendiente (P2/futuro): pruebas unitarias automatizadas de backend/ETL, pruebas de
integración `Scraper → RAW → ETL → PostgreSQL` y `PostgreSQL → API → Flutter` como suites
repetibles (hoy se hicieron manualmente), pruebas de aceptación formales de la sección 51
del documento original.

---

## 17. Prioridades de implementación — estado

### P0 (núcleo obligatorio) — ✅ completo
Integración de 5 supermercados, RAW histórico, ejecuciones, ETL, ciclo de vida, protección
contra falsas descontinuaciones, homologación (incl. cross-run y validación de integridad),
API versionada, búsqueda, detalle, comparación, mejor precio, ahorro, fecha de
actualización, app móvil base.

### P1 (funcionalidad completa) — ✅ completo
Historial visual mensual con detalle por mes, listas de compra y su comparación de costo
(incl. compra distribuida), establecimientos (UI + backend, sin datos sembrados),
geolocalización con manejo de timeout, precio unitario, fecha de actualización por fuente en
Configuración, agrupación real de resultados homologados, sistema de diseño visual unificado.

### P2 (evolución) — no iniciado
Alertas de precio, favoritos, OCR de tickets, registro colaborativo, recomendaciones,
predicción, análisis de tendencias avanzado, historial de compras del propio usuario (RF
distinto del historial de precios: aquí se trataría de registrar lo que el usuario compró,
no la evolución del precio de mercado de un producto). No comprometen el núcleo si se
agregan después.

---

## 18. Trabajo de seguimiento conocido

- **Datos de establecimientos físicos:** el schema y los endpoints existen; falta un
  proceso de scraping/carga de `physical_stores` para que `/stores` deje de devolver listas
  vacías.
- **Suites de test automatizadas:** backend y ETL se verificaron manualmente en esta fase;
  falta formalizarlo en `backend/tests/` y un runner de pruebas de ETL.
- **REJECTED en homologación:** reservado en el schema pero sin flujo de revisión manual que
  lo genere — queda como funcionalidad P2.
- **Carulla, Jumbo, Olímpica:** los conectores de scraping existen (`scraper/connectors/`),
  pero sólo Carulla tiene una carga real en la base de datos de desarrollo (1026
  `source_products`) al momento de este documento; Jumbo y Olímpica todavía no se han
  ejecutado en este ambiente. Configuración lo refleja honestamente ("sin datos todavía") en
  lugar de simular una fecha de actualización.

---

## 19. Criterio de aceptación

Convenia demuestra ser un sistema histórico de apoyo a la decisión de compra (no una simple
consulta de precio actual) cuando, para un producto cualquiera, puede responder:

- ¿Dónde está disponible hoy, a qué precio, y desde cuándo se observó ese precio?
- ¿Cuál ha sido su precio mínimo/máximo/promedio histórico?
- ¿Cuánto se ahorra comprándolo en el supermercado más barato frente al más caro?
- ¿Sigue vigente ese producto, o fue descontinuado — y si fue descontinuado, conserva su
  historial?
- ¿Puede reconstruirse el origen exacto (ejecución, RAW) de cualquier precio mostrado?

Los cinco puntos anteriores están implementados y verificados contra datos reales al cierre
de este documento.
