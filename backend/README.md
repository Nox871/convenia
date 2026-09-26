# Convenia — Backend API

API REST del proyecto Convenia. Es el backend único que consume la app
móvil (y, en el futuro, cualquier otro cliente).

## Stack

- Python 3 + FastAPI
- PostgreSQL (base `convenia`, esquema versionado en `database/migrations/`)
- SQLAlchemy Core (sin ORM: las consultas son SQL explícito en
  `app/repositories/`, igual que en el ETL, para no duplicar la definición
  del esquema en dos sitios)
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
│   │   ├── category_bucket.py # Puente al clasificador de categorías compartido
│   │   └── product_ref.py     # Codifica/decodifica el id opaco de producto (ver abajo)
│   ├── schemas/                # Modelos Pydantic de request/response
│   ├── repositories/           # SQL parametrizado — única capa que toca la BD
│   ├── services/                # Reglas de negocio, agnóstico de HTTP y de SQL
│   └── routers/                 # Endpoints HTTP (delgados, delegan a services)
├── requirements.txt
└── README.md
```

Separación de capas: `routers` (HTTP) → `services` (negocio) →
`repositories` (SQL). Los routers y schemas no cambian aunque cambie de
dónde vienen los datos.

## Decisión arquitectónica: id opaco de producto

Cada producto se identifica con un id con prefijo, para que la API no
dependa de si un producto ya está homologado entre supermercados o no:

- `sp-123` → `source_products.id = 123` (un producto de un solo
  supermercado, sin homologar).
- `p-45` → `products.id = 45` (producto canónico ya homologado, con datos
  de 2 o más supermercados).

`GET /api/v1/products` devuelve ambos tipos combinados en un mismo
listado: los homologados agrupados con su mejor precio, y los sueltos con
el precio de su único supermercado. `/products/{id}`, `/prices` y
`/compare` funcionan igual sin importar el prefijo:
`app/repositories/product_repository.py` decide, según él, si lee de
`source_products` o de `products` + `product_matches`.

## Configuración

El backend reutiliza el **mismo `.env`** que usa el ETL, en la raíz del
proyecto. Ver `.env.example` para la lista completa de variables y sus
valores por defecto.

## Instalación

```bash
python -m venv backend/.venv
backend/.venv/Scripts/pip install -r backend/requirements.txt
```

## Ejecutar

Desde `backend/`:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- API: http://localhost:8000
- Swagger UI: http://localhost:8000/docs
- OpenAPI JSON: http://localhost:8000/openapi.json

## Endpoints

Todos bajo `/api/v1/`, excepto el health check.

| Recurso | Endpoints |
|---|---|
| Sistema | `GET /api/health` |
| Supermercados | `GET /supermarkets`, `GET /supermarkets/{id}` |
| Categorías | `GET /categories` |
| Productos | `GET /products` (`?q=&supermarket=&sort=&page=&limit=`), `GET /products/{id}` |
| Precios | `GET /products/{id}/prices`, `GET /products/{id}/compare` |
| Historial | `GET /products/{id}/history` (`?month=YYYY-MM`), `GET /products/{id}/history/monthly` |
| Listas de compra | `GET/POST /lists`, `GET/PUT/DELETE /lists/{id}`, `POST /lists/{id}/items`, `PUT/DELETE /lists/{id}/items/{item_id}`, `GET /lists/{id}/cost`, `GET /lists/{id}/cost/distributed` |
| Establecimientos | `GET /stores`, `GET /stores/nearby` (`?lat=&lon=&radius_km=`) |

`GET /products` acepta `page` (default 1) y `limit` (default 20, máx.
100), y devuelve `items` + `pagination` (`total`, `total_pages`,
`has_next`, `has_prev`).

## Reglas de negocio aplicadas

- Sólo se usan `price_observations` con `available = TRUE`.
- El precio y la moneda nunca se inventan: si un producto no tiene precio
  disponible en un supermercado, ese campo viene `null`, nunca `0`.
- El mejor precio es el mínimo respetando moneda.
- `/compare` siempre devuelve una fila por cada supermercado activo,
  tenga o no oferta para ese producto — el número de filas nunca se asume
  fijo.
- El costo de una lista sólo declara "conviene" al supermercado donde la
  lista está completa; nunca compara un total parcial contra uno completo.

## No incluido en esta fase

Autenticación de usuarios, pagos, OCR de comprobantes, recomendaciones,
carrito de compra.
