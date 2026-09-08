# Convenia — App móvil (Flutter)

"Antes de comprar, elige dónde." App Android que consulta el backend REST de
Convenia (`E:\convenia\backend`) para comparar precios entre D1 y Éxito.

Todo el código Dart (`lib/`, `pubspec.yaml`) está escrito, `pub get` ya se
corrió con éxito (`pubspec.lock` presente, resuelto contra Flutter 3.47.2),
y el scaffolding nativo de Android (`android/`) **ya está generado** —
ya se puede compilar y correr. Los dos ajustes manuales que requería el
`AndroidManifest.xml` (tráfico HTTP en claro y permiso de Internet) ya
están aplicados en este repo.

## Requisitos

- Flutter SDK (ya lo tienes instalado)
- Un emulador Android (AVD) creado en Android Studio, **o** un teléfono
  Android conectado por USB con la "depuración USB" activada
- Backend de Convenia corriendo (`E:\convenia\backend`) — ver su propio
  README; ahora mismo ya está corriendo en `http://127.0.0.1:8000`

Verifica que todo esté en orden con:
```bash
flutter doctor
```
(si marca algo en rojo relacionado con Android, resuélvelo antes de seguir)

## Cómo correrlo, paso a paso

**Opción A — Android Studio (más simple si nunca corriste una app Flutter):**
1. Abre Android Studio → "Open" → selecciona la carpeta `E:\convenia\mobile`.
2. Espera a que termine de indexar/sincronizar (barra de progreso abajo).
3. En la barra superior, junto al botón ▶ (Run), hay un selector de
   dispositivo: elige un emulador ya creado (o crea uno nuevo con
   "Device Manager" si no tienes ninguno — cualquier Pixel con Android 12+
   funciona bien) o tu teléfono si está conectado por USB y aparece ahí.
4. Presiona ▶. La primera vez tarda varios minutos (descarga/compila
   Gradle). Cuando termine, se abre la app en el emulador/teléfono.

**Opción B — Terminal:**
```bash
cd E:\convenia\mobile
flutter devices          # confirma que ves un emulador o tu teléfono en la lista
flutter run               # compila e instala; deja la terminal abierta (hot reload con 'r')
```

Con cualquiera de las dos opciones, si usas un **emulador**, no necesitas
hacer nada más: la app ya apunta por defecto a `http://10.0.2.2:8000`, que
es como el emulador ve al backend corriendo en tu propia máquina.

Si usas un **teléfono físico** por USB, necesitas dos cosas adicionales
(ver la sección siguiente): que el backend escuche en todas las interfaces,
no solo en `localhost`, y decirle a la app la IP de tu PC en la red Wi-Fi.

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

## Compatibilidad con la homologación (`products`/`product_matches`)

Cuando corras el scraping/ETL/homologación (de forma manual, ver
`E:\convenia\etl\README.md`) y `/api/products` empiece a devolver ids
canónicos (`p-*`) para productos ya homologados entre D1 y Éxito, **no
hace falta cambiar nada en la app móvil**: `ProductRepository` y las
pantallas ya tratan el id como una cadena opaca de extremo a extremo, y
`ComparisonBanner` ya maneja el caso de 2+ ofertas reales por producto (ver
sección anterior). Es justamente el propósito de ese diseño.

## Estado del entorno / pruebas realizadas

`flutter`/`dart` no son accesibles desde el entorno de trabajo donde se
escribió y revisó este código (por eso no se pudo correr `flutter analyze`
ni `flutter run` desde ahí), pero en tu máquina real ya están instalados:
existe `android/` generado por `flutter create`, `pubspec.lock` resuelto
contra Flutter 3.47.2, y ya corregí ahí mismo los dos ajustes que ese
scaffolding necesitaba para funcionar con este backend (ver más abajo) y el
test de ejemplo que trae la plantilla por defecto (referenciaba un widget
`MyApp` que no existe en esta app; lo reemplacé por un smoke test real de
Home).

Se validó, mediante revisión manual línea por línea de cada archivo en
`lib/` y del `android/AndroidManifest.xml` generado:
- Las respuestas reales de los 4 endpoints usados (`/api/products`,
  `/api/products/{id}`, `/api/products/{id}/compare`) contra el backend
  corriendo con datos reales de D1, confirmando que cada modelo Dart
  (`lib/models/*.dart`) mapea exactamente las claves y tipos devueltos.
- Revisión de cada widget en busca de overflows en anchos de 360 px (la
  fila de precio de `ProductCard` usa `Wrap` en vez de `Row` por esto).
- Revisión de consistencia de imports, tipos y nulabilidad en todo `lib/`.
- `android/app/src/main/AndroidManifest.xml`: le faltaban
  `android:usesCleartextTraffic="true"` (el backend es HTTP, no HTTPS) y
  `<uses-permission android:name="android.permission.INTERNET"/>` — ya
  agregados.
- `test/widget_test.dart`: reemplazado el test de la plantilla por uno que
  sí corresponde a esta app (verifica que Home muestra el logo, el título,
  el buscador y las 4 búsquedas frecuentes).

**Pendiente, solo a cargo tuyo porque requiere el SDK/emulador que no
tengo accesible desde aquí:** correr `flutter run` (o abrir el proyecto en
Android Studio, ver "Cómo correrlo" arriba) y confirmar visualmente el
flujo Home → Resultados → Comparación contra el backend real. Si algo no
compila o se ve distinto a lo esperado, dime el mensaje de error o una
captura y lo corrijo puntualmente.
