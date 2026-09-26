# Convenia — App móvil (Flutter)

"Antes de comprar, elige dónde." App Android que consulta la API REST de
Convenia (`../backend`) para comparar precios entre supermercados, ver el
historial de precios de un producto y planificar una lista de compra.

## Requisitos

- Flutter SDK
- Un emulador Android (AVD) o un teléfono Android por USB con depuración
  activada
- El backend de Convenia corriendo (ver `../backend/README.md` si existe,
  o la sección "Backend" del `docs/ERS.md` del proyecto)

Verifica el entorno con:
```bash
flutter doctor
```

## Cómo correrlo

```bash
cd mobile
flutter pub get
flutter run
```

Si usas un **emulador**, no hace falta nada más: la app apunta por defecto
a `http://10.0.2.2:8000`, que es como el emulador ve al `localhost` de la
máquina donde corre.

Si usas un **teléfono físico** por USB/Wi-Fi, el backend debe escuchar en
todas las interfaces, no solo en `localhost`:
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
y hay que compilar la app apuntando a la IP de esa máquina en la red:
```bash
flutter run --dart-define=API_BASE_URL=http://<IP-de-tu-red>:8000
```

## Configuración de la URL del backend

La URL base se define en tiempo de compilación (`ApiConfig` en
`lib/core/api_config.dart`), nunca hardcodeada en el código:

```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
```

## Estructura

```
lib/
├── main.dart
├── core/           # theme (tokens de diseño), api_config, formatters, excepciones
├── models/         # espejo 1:1 de los schemas Pydantic del backend
├── services/       # ApiClient: único punto que hace HTTP
├── repositories/    # una por recurso (productos, listas, tiendas, supermercados)
├── state/           # ChangeNotifier por pantalla
├── screens/          # Inicio, Resultados, Detalle, Historial, Listas, Establecimientos, Configuración
└── widgets/           # componentes compartidos (tarjetas, badges, estados de carga/vacío/error)
```

Flujo de datos: `screens` (UI) → `state` (lógica/estado, `ChangeNotifier`) →
`repositories` (dominio) → `services` (HTTP) → backend REST. Los widgets
nunca llaman HTTP directamente.

## Endpoints consumidos

| Recurso | Endpoints |
|---|---|
| Productos | `GET /api/v1/products`, `GET /api/v1/products/{id}`, `GET /api/v1/products/{id}/compare`, `GET /api/v1/products/{id}/prices` |
| Historial de precios | `GET /api/v1/products/{id}/history`, `GET /api/v1/products/{id}/history/monthly` |
| Listas de compra | `GET/POST /api/v1/lists`, `GET/PUT/DELETE /api/v1/lists/{id}`, `POST/PUT/DELETE /api/v1/lists/{id}/items`, `GET /api/v1/lists/{id}/cost`, `GET /api/v1/lists/{id}/cost/distributed` |
| Establecimientos | `GET /api/v1/stores`, `GET /api/v1/stores/nearby` |
| Supermercados | `GET /api/v1/supermarkets` |

## Comportamiento del listado de Resultados

`GET /api/v1/products` agrupa automáticamente los productos que el motor de
homologación del backend ya reconoció como el mismo producto en varios
supermercados (mostrando "Desde $X en N supermercados"); los que todavía no
tienen esa coincidencia se listan sueltos, con su precio de un único
supermercado. La app no decide esto por su cuenta: simplemente muestra lo
que la API devuelve, así que la proporción de productos agrupados crece
sola a medida que la homologación avanza en el backend, sin cambios en el
código móvil.
