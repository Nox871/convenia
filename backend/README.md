# Convenia — Backend API

API REST del proyecto Convenia. Es el backend único que consumirán tanto la
app móvil (prioridad actual) como, más adelante, el cliente web — ambos como
clientes de la misma API.

## Stack

- Python 3 + FastAPI
- PostgreSQL (base `convenia` ya existente, esquema administrado fuera del backend)
- SQLAlchemy Core (sin ORM: las consultas son SQL explícito en `app/repositories/`,
  igual que en el ETL, para no duplicar la definición del esquema en dos sitios)
- Pydantic / pydantic-settings

## Estructura

```
backend/
├── app/
│   ├── main.py               # FastAPI app, CORS, manejo de errores, routers
│   ├── core/
│   │   ├── config.py          # Settings (lee el .env del proyecto)
│   │   ├── database.py        # Engine SQLAlchemy + dependencia get_db()
│   │   ├── exceptions.py      # Excepciones de dominio (InvalidParameterError, NotFoundError)
│   │   └── product_ref.py     # Codifica/decodifica el id opaco de producto (ver abajo)
│   ├── schemas/                # Modelos Pydantic de request/response
│   ├── repositories/           # SQL parametrizado — única capa que toca la BD
│   ├── services/                # Reglas de negocio, agnóstico de HTTP y de SQL
│   └── routers/                 # Endpoints HTTP (delgados, delegan a services)
├── requirements.txt
└── README.md
```

Separación de capas: `routers` (HTTP) -> `services` (negocio) -> `repositories`
(SQL). Los routers y schemas no cambian aunque cambie de dónde vienen los datos.

## Decisión arquitectónica clave: id opaco de producto

Hoy `products` y `product_matches` están vacías porque la homologación entre
supermercados todavía no corrió. Para no acoplar la API a `source_products`,
cada producto se identifica con un id con prefijo:

- `sp-123` -> `source_products.id = 123` (un producto de un solo supermercado, sin homologar)
- `p-45` -> `products.id = 45` (producto canónico ya homologado, con 1+ supermercados)

Así, `GET /api/products` hoy devuelve ids `sp-*` (uno por `source_product`,
porque no hay matches confirmados). Cuando exista homologación, algunos
productos empezarán a devolver ids `p-*` que agrupan varios supermercados —
y `/api/products/{id}`, `/prices` y `/compare` seguirán funcionando igual,
porque `app/repositories/product_repository.py` decide, según el prefijo, si
lee de `source_products` o de `products` + `product_matches`. Sólo ese
archivo necesita cambiar; no los endpoints.

## Configuración

El backend reutiliza el **mismo `.env`** que usa el ETL, en la raíz del
proyecto (`E:\convenia\.env`), con las variables:

```
DB_HOST=...
DB_PORT=...
DB_NAME=...
DB_USER=...
DB_PASSWORD=...
```

No se necesitan variables nuevas obligatorias. Opcionalmente:

```
BACKEND_CORS_ORIGINS=http://localhost:3000,http://localhost:19006
```

## Instalación

```bash
python -m venv backend/.venv
backend/.venv/Scripts/pip install -r backend/requirements.txt
```

## Ejecutar

Desde la raíz del proyecto (`E:\convenia`):

```bash
backend/.venv/Scripts/python.exe -m uvicorn app.main:app --app-dir backend --reload --port 8000
```

- API: http://localhost:8000
- Swagger UI: http://localhost:8000/docs
- OpenAPI JSON: http://localhost:8000/openapi.json

## Endpoints

| Método | Ruta                              | Descripción                              |
|--------|-----------------------------------|-------------------------------------------|
| GET    | `/api/health`                     | Health check                              |
| GET    | `/api/products`                   | Búsqueda/listado paginado de productos    |
| GET    | `/api/products/{id}`              | Detalle de un producto                    |
| GET    | `/api/products/{id}/prices`       | Ofertas de precio disponibles del producto|
| GET    | `/api/products/{id}/compare`      | Comparación de ofertas + mejor precio     |

`GET /api/products` acepta `q`, `supermarket`, `page` (default 1) y `limit`
(default 20, máx. 100), y devuelve `items` + `pagination` (`total`,
`total_pages`, `has_next`, `has_prev`).

## Reglas de negocio aplicadas

- Sólo se usan `price_observations` con `available = TRUE`.
- El precio y la moneda nunca se inventan: si un producto no tiene precio
  disponible, `offers` viene vacío y `best_price` es `null`.
- `best_price` es el mínimo respetando moneda (hoy siempre COP en los datos
  cargados).
- Se distingue explícitamente `source_products.external_id` (id del
  supermercado de origen, vive dentro de `raw_data`/no se expone como id de
  producto) del id canónico de `products`.

## No incluido en esta fase

Autenticación, usuarios, pagos, OCR, IA/recomendaciones, carrito, rutas,
integración con mapas, frontend. Se agregará en fases posteriores.
