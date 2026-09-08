# Scrapers — D1, Éxito, Carulla, Jumbo, Olímpica

Adquisición automatizada de productos y precios, delimitada a categorías de
**canasta familiar** (alimentación + aseo/hogar de consumo frecuente).

## Estado actual

> **La ejecución real del scraping (correr los comandos de abajo) se
> realiza manualmente, queda a cargo de quien opere el proyecto.**

- D1 y Carulla exponen sus categorías de forma **plana** (rutas de un solo
  segmento, ej. `/frutas-y-verduras`).
- Éxito y Olímpica las exponen bajo un **hub intermedio**
  (`/mercado/home` y `/supermercado` respectivamente) — la home no enlaza
  todas las subcategorías directamente, hay que entrar a ese hub.
- Jumbo expone un mega-menú muy completo directamente en la home (rutas
  planas de 1-2 segmentos, sin necesidad de hub).
- Éxito, Carulla, Jumbo y Olímpica son todos **VTEX**; comparten el mismo
  formato de consulta al catálogo (`_endpoint_y_params_vtex`) y la misma
  forma de extraer la categoría más específica (`categories[0]`, no
  `categories[-1]`) — ambos fueron bugs reales encontrados y corregidos.
- D1 no es VTEX: raspa el HTML de la tienda directamente.

## Estructura

```
scraper/
├── core/
│   └── category_filter.py   # clasificador de categorías por palabras clave (compartido por los 5)
└── connectors/
    ├── d1/scraper.py
    ├── exito/scraper.py
    ├── carulla/scraper.py
    ├── jumbo/scraper.py
    └── olimpica/scraper.py
```

## Filtro de categorías

Ver los comentarios en `core/category_filter.py` para el detalle completo.
En resumen: cada categoría (por su slug de URL o su nombre real del
catálogo) se normaliza — incluye decodificar `%XX` de la URL, para no
perder categorías con tildes como "decoración" — y se compara contra dos
conjuntos de palabras clave:

- `PALABRAS_EXCLUSION` (tecnología, licores, moda, electrodomésticos,
  vestuario, automóvil, ...)
- `PALABRAS_INCLUSION` (arroz, lácteo, aseo, carne, verdura, ...)

Se rechaza por defecto si no coincide con ninguna — es preferible dejar
fuera una categoría desconocida que colar una fuera de alcance. Para
ampliar o ajustar el alcance, basta con editar esas dos listas; no hace
falta tocar la lógica de scraping ni de extracción de productos, y el
cambio aplica automáticamente a los 5 conectores a la vez.

## Cómo ejecutar (manual, cuando corresponda)

Desde `E:\convenia`, con el venv del scraper, con **cwd = `scraper/`**:

```bash
scraper/.venv/Scripts/python.exe -m connectors.d1.scraper
scraper/.venv/Scripts/python.exe -m connectors.exito.scraper
scraper/.venv/Scripts/python.exe -m connectors.carulla.scraper
scraper/.venv/Scripts/python.exe -m connectors.jumbo.scraper
scraper/.venv/Scripts/python.exe -m connectors.olimpica.scraper
```

`MAX_CATEGORIAS` y `MAX_PAGINAS_POR_CATEGORIA` son únicamente un límite
técnico de volumen — no definen qué categorías son relevantes, eso ya lo
decide el filtro anterior.

Cada scraper imprime, al finalizar, un reporte de categorías encontradas /
aceptadas / descartadas y ejemplos de cada una.

## Después de scrapear: ETL y homologación

```bash
scraper/.venv/Scripts/python.exe -m etl.run_etl ALL            # (cwd: E:\convenia)
scraper/.venv/Scripts/python.exe -m etl.homologacion.run
```

Ver `etl/README.md` y `etl/homologacion/README.md` para el detalle de
ambos pasos.
