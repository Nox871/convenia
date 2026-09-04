# Convenia — App móvil (Flutter)

"Antes de comprar, elige dónde." App Android que consulta el backend REST de
Convenia (`E:\convenia\backend`) para comparar precios entre D1 y Éxito.

Este proyecto se escribió con todo el código Dart (`lib/`, `pubspec.yaml`)
pero **sin el scaffolding nativo de Android** (`android/`), porque en la
máquina donde se generó no había Flutter SDK instalado para correr
`flutter create` de forma verificable. Ver "Puesta en marcha" abajo — es un
único comando.

## Requisitos

- Flutter SDK (canal stable) — https://docs.flutter.dev/get-started/install/windows
- Android Studio o al menos el Android SDK + un emulador (AVD) o dispositivo físico con depuración USB
- Backend de Convenia corriendo (`E:\convenia\backend`, ver su propio README)

Verifica con:
```bash
flutter doctor
```

## Puesta en marcha (una sola vez)

Desde `E:\convenia\mobile`:

```bash
flutter create --platforms=android --org com.convenia --project-name convenia_mobile .
flutter pub get
```

(`--platforms=android` porque el objetivo de esta etapa es solo Android; se
puede agregar iOS más adelante con `flutter create --platforms=ios .`.)

Esto genera `android/`, `ios/`, etc. sin tocar `lib/` ni `pubspec.yaml`
(puede pedir confirmar sobrescribir `pubspec.yaml`/`.gitignore`; si pregunta,
dile que NO sobrescriba `pubspec.yaml`, o vuelve a pegar el que está en este
repo si lo sobrescribe).

### Pasos manuales obligatorios después de `flutter create`

1. **Tráfico HTTP en claro (cleartext).** El backend corre en `http://`
   (no `https://`) en desarrollo. Android 9+ bloquea HTTP por defecto. En
   `android/app/src/main/AndroidManifest.xml`, agrega el atributo en la
   etiqueta `<application ...>`:
   ```xml
   <application
       android:usesCleartextTraffic="true"
       ...>
   ```
   (Solo para desarrollo. Si más adelante el backend sirve por HTTPS, se
   puede quitar.)

2. **Permiso de Internet.** Verifica que el mismo archivo tenga:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```
   Las plantillas recientes de `flutter create` ya lo incluyen, pero
   confírmalo.

## Configuración de la URL del backend

La URL base se define en tiempo de compilación (`ApiConfig` en
`lib/core/api_config.dart`), nunca hardcodeada:

```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
```

- **Emulador Android** (valor por defecto, no requiere flag): el backend
  debe correr en `127.0.0.1:8000` (como ya lo hace por defecto con
  `uvicorn app.main:app --app-dir backend --port 8000`); `10.0.2.2` es el
  alias que usa el emulador para llegar al `localhost` del computador
  anfitrión.

- **Dispositivo físico Android** (misma red Wi-Fi que el computador): el
  backend debe escuchar en todas las interfaces, no solo localhost:
  ```bash
  backend/.venv/Scripts/python.exe -m uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port 8000
  ```
  Averigua la IP LAN del computador con `ipconfig` (ej. en esta máquina fue
  `192.168.80.28`, puede variar) y compila apuntando ahí:
  ```bash
  flutter run --dart-define=API_BASE_URL=http://192.168.80.28:8000
  ```

## Ejecutar

```bash
flutter run
# o, para dispositivo físico:
flutter run --dart-define=API_BASE_URL=http://<IP-LAN-DEL-PC>:8000
```

## Estructura

```
lib/
├── main.dart
├── core/            # theme (design tokens), api_config, formatters, excepciones
├── models/          # espejo 1:1 de los schemas Pydantic reales del backend
├── services/        # ApiClient: único punto que hace HTTP
├── repositories/     # ProductRepository: API de dominio sobre ApiClient
├── state/            # ChangeNotifier: SearchResultsController, ProductDetailController
├── screens/           # HomeScreen, ResultsScreen, ProductDetailScreen
└── widgets/            # ProductCard, ComparisonBanner, estados loading/empty/error, etc.
```

Flujo de datos: `screens` (UI) → `state` (lógica/estado, `ChangeNotifier`) →
`repositories` (dominio) → `services` (HTTP) → backend REST. Los widgets
nunca llaman `http` directamente.

## Endpoints consumidos

| Endpoint | Uso |
|---|---|
| `GET /api/products?q=&supermarket=&page=&limit=` | Home (búsquedas frecuentes) y Resultados (búsqueda + filtro + paginación) |
| `GET /api/products/{id}` | Encabezado de la pantalla de Comparación (nombre, marca, categoría, imagen) |
| `GET /api/products/{id}/compare` | Ofertas + mejor precio + ahorro en la pantalla de Comparación |

`GET /api/products/{id}/prices` está implementado en `ProductRepository`
pero no se usa hoy: `/compare` ya devuelve el mismo listado de ofertas más el
`best_price` que la comparación necesita, así que usarlo también sería una
llamada redundante. Queda listo por si se necesita una vista de "solo
precios" sin comparación.

## Decisión importante: por qué la tarjeta de Resultados muestra un solo precio

El prototipo visual muestra, en cada tarjeta de la lista, el precio en D1 y
en Éxito lado a lado. **Eso no es posible hoy sin inventar datos**: 
`GET /api/products` devuelve una fila por `source_product` de un único
supermercado (ver `backend/app/repositories/product_repository.py`), porque
la homologación entre supermercados (`products` + `product_matches`) todavía
no se ejecutó — así quedó explícitamente decidido en la fase anterior del
backend. No hay, hoy, un mismo producto con precios conocidos en ambos
supermercados a la vez.

Por eso:
- **`ProductCard`** (lista de Resultados) muestra el precio real de un solo
  supermercado, con su badge de color — nunca un precio ficticio para el
  otro.
- **La comparación real** ("Te conviene comprarlo en X", ahorro, segunda
  opción) vive en la pantalla de Detalle, que llama a `/compare` por
  producto. Hoy, como cada producto tiene una sola oferta real, `/compare`
  devuelve un único offer y la pantalla lo muestra como "Precio disponible
  en X" sin afirmar una comparación que no existe.
- El código de `ComparisonBanner` y de los filtros "Mejor en D1" / "Mejor en
  Éxito" ya está preparado para el caso de 2+ ofertas reales por producto: en
  cuanto exista homologación y `/compare` empiece a devolver más de una
  oferta para un mismo id, el banner completo (ganador + ahorro + segunda
  opción) se activa solo, sin cambios de código.

No se modificó el backend para esto — es un límite real de los datos
actuales, no un bug.

## Pruebas realizadas

No se pudo ejecutar `flutter analyze` / `flutter run` en la máquina de
desarrollo (Flutter SDK no instalado). Se validó en su lugar:
- Las respuestas reales de los 4 endpoints usados (`/api/products`,
  `/api/products/{id}`, `/api/products/{id}/compare`) contra el backend
  corriendo con datos reales de D1/Éxito, confirmando que cada modelo Dart
  (`lib/models/*.dart`) mapea exactamente las claves y tipos devueltos.
- Revisión manual de cada widget en busca de overflows en anchos de 360 px
  (la fila de precio de `ProductCard` se implementó con `Wrap` en vez de
  `Row` por esto).

Pendiente cuando el entorno tenga Flutter instalado: `flutter analyze`,
`flutter test` (aún no hay tests escritos) y verificación visual en un AVD.
