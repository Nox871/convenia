# Sistema de diseño e interacción — Convenia

**Versión del documento:** 1.0
**Fecha:** 2026-09-08
**Alcance:** describe cómo se construyó gráficamente la aplicación móvil — principios,
paleta, tipografía, y las decisiones de jerarquía tomadas en cada pantalla — para que el
criterio de diseño quede documentado y sea trazable, tal como lo exige `docs/ERS.md` para
el resto del sistema. No es un documento aspiracional: cada regla descrita aquí está
implementada en `mobile/lib/core/theme.dart` y en las pantallas referenciadas.

---

## 1. Principio rector

Antes de agregar cualquier elemento a una pantalla, se aplica una sola pregunta de
filtrado:

> **¿Esto ayuda al usuario a decidir dónde comprar?**

Si la respuesta es no, el elemento se retira o se degrada visualmente (menor peso, menor
jerarquía, o se mueve a un panel secundario). Esta regla es la razón concreta detrás de
varias decisiones documentadas más abajo: por qué los supermercados no tienen color propio,
por qué una oferta sin dato no se muestra con el mismo peso que una con dato real, y por qué
"Comprar distribuido" sólo aparece cuando representa un ahorro real.

El objetivo declarado no es una app bonita por sí misma, sino una app en la que, al cerrarla,
el usuario piense: *"Entiendo lo que estoy viendo. Ahora sé dónde me conviene."*

---

## 2. Flujo de experiencia

La navegación completa de la app —desde abrir la pantalla de inicio hasta agregar un
producto a una lista— sigue un mismo hilo conductor de cinco pasos:

```
BUSCAR → ENCONTRAR → COMPARAR → ENTENDER → ELEGIR
```

| Paso | Pantalla(s) | Pregunta que responde |
|---|---|---|
| Buscar | Inicio | ¿Qué producto necesito? |
| Encontrar | Resultados | ¿Cuáles son las alternativas disponibles? |
| Comparar | Detalle de producto | ¿Qué tan diferentes son estas alternativas? |
| Entender | Historial | ¿Es un precio normal o una anomalía? |
| Elegir | Detalle → Agregar a lista, Listas → Comprar distribuido | ¿Dónde compro, y cuánto me cuesta hacerlo? |

Cada pantalla tiene **una sola acción primaria** coherente con el paso del flujo en el que
se encuentra (buscar, ver un resultado, comparar un precio, agregar a una lista), evitando
que compitan dos llamados a la acción de igual peso visual en la misma vista.

---

## 3. Sistema de diseño visual

### 3.1 Paleta de marca

Definida como constantes en `AppColors` (`mobile/lib/core/theme.dart`), nunca como colores
sueltos dentro de un widget:

| Token | Valor | Uso |
|---|---|---|
| `brandIndigo` | `#5B4FE9` | Acción principal por pantalla; estado "seleccionado" / mejor precio |
| `ink` | `#17171C` | Texto principal |
| `softIvory` | `#F7F5EF` | Fondo base de la app |
| `white` | `#FFFFFF` | Superficies elevadas (tarjetas) |
| `lavenderMist` | `#ECEAFF` | Superficie neutral (incluye el badge de supermercado) |
| `success` | `#16805C` | Ahorro, dato vigente |
| `warning` | `#B7791F` | Lista incompleta, dato por confirmar |
| `error` | `#C94A4A` | Error de conexión, estado fallido |

**Regla 80/15/5:** `softIvory`/`white` dominan los fondos (≈80%), `ink` y sus variantes de
opacidad cubren la jerarquía de texto (≈15%), y `brandIndigo` queda reservado como acento —
la acción principal de cada pantalla y el precio ganador (≈5%). Los colores semánticos
(`success`/`warning`/`error`) se usan exclusivamente para comunicar un estado, nunca como
decoración.

**Regla de neutralidad por supermercado:** ningún supermercado tiene un color propio en la
interfaz (antes del rediseño, D1 se mostraba en rojo y Éxito en ámbar). Todos los badges de
supermercado (`widgets/supermarket_badge.dart`) usan el mismo par `lavenderMist`/`ink`; la
identificación es por **nombre**, no por color. Esta decisión es deliberada: colorear cada
supermercado sesgaría visualmente la comparación antes de que el usuario lea el precio.

### 3.2 Tipografía

Dos familias, vía `google_fonts`, sin variantes adicionales:

- **Manrope** — títulos de pantalla, nombres de producto, precios (`AppText.hero`,
  `screenTitle`, `sectionTitle`, `priceMain`, `priceCard`, `productName`).
- **Inter** — cuerpo de texto, metadatos, etiquetas (`AppText.body`, `caption`).

La separación es funcional, no decorativa: Manrope se reserva para lo que el usuario debe
poder leer de un vistazo (un precio, un nombre de producto); Inter para todo lo que requiere
lectura continua o es secundario.

### 3.3 Componentes de estado obligatorios

Toda pantalla que depende de una llamada de red implementa los mismos tres estados
(`widgets/state_views.dart`), nunca sólo el camino feliz:

- **Cargando** — indicador, sin contenido fantasma.
- **Vacío** — mensaje honesto sobre por qué no hay datos (p. ej. "Todavía no tenemos tiendas
  físicas registradas"), nunca un placeholder inventado.
- **Error** — mensaje + acción de reintentar.

---

## 4. Jerarquía por pantalla

### 4.1 Inicio

Única pantalla sin llamada de red al abrir la app. Un solo campo de búsqueda como acción
primaria; accesos rápidos por categoría como acción secundaria. No incluye ningún indicador
comparativo entre supermercados (el "Mejor en D1 / Mejor en Éxito" que existía antes del
rediseño se retiró: asumía sólo dos fuentes y quedaba falso apenas se homologa un tercer
supermercado).

### 4.2 Resultados (patrón "Google Flights")

Inspirada en la forma en que Google Flights presenta vuelos: una lista densa pero legible,
ordenable por un criterio explícito, sin forzar filtros antes de ver resultados. El orden
disponible es **menor precio** (por defecto) o **más reciente**; "más cercano" está definido
en la interfaz pero deshabilitado con una explicación visible mientras no exista una
ubicación física real que comparar (ver `docs/ERS.md` §11.1 y §18). Los filtros avanzados
(por supermercado específico, por ejemplo) quedan ocultos detrás de un panel secundario en
vez de ocupar una barra permanente — se muestran sólo cuando el usuario los pide.

Cada tarjeta de producto se adapta al número real de ofertas: un producto homologado entre
varios supermercados muestra "Desde \$X en N supermercados"; un producto que sólo existe en
una fuente muestra su precio único, sin insinuar una comparación que no existe. La interfaz
nunca asume un número fijo de supermercados (ni 2, ni 5): se adapta a cuantas ofertas reales
haya.

### 4.3 Detalle de producto

Orden vertical fijo, de arriba hacia abajo:

```
Producto (imagen, nombre, marca, categoría en lenguaje natural)
   → Precio (mejor precio, ahorro frente al más caro)
   → Precios registrados / Disponibilidad
   → Actualidad (dato vigente o desactualizado)
   → Historial (acceso al detalle mensual)
   → Agregar a lista
```

Tres decisiones de lenguaje honesto, tomadas explícitamente para no sobre-prometer:

- La categoría se muestra en una etiqueta legible (p. ej. "Despensa") en vez de la ruta
  técnica cruda que expone el sitio de origen (p. ej. `/Despensa/Granos/Arroz/`).
- El título de la sección de precios es **"Disponibilidad"** cuando sólo hay una oferta con
  dato real, y **"Precios registrados"** cuando hay dos o más — nunca "Todas las ofertas",
  porque ese texto implicaba comparación incluso cuando sólo existía un dato.
- Las filas sin dato ("Sin datos") se ocultan por completo cuando el producto tiene 0 o 1
  oferta real: mostrarlas como si fueran una fila más de la comparación añade ruido sin
  aportar ninguna decisión al usuario, en un momento en que la mayoría de los productos
  recolectados todavía no están homologados entre supermercados.

### 4.4 Historial

La pantalla que más cambió en el rediseño. La pregunta que debe responder no es "¿cuánto
costaba antes?" sino **"¿qué tan normal es el precio actual?"**. Para eso, la interacción
tiene dos niveles:

1. **Resumen mensual** — una barra por mes con dato real (altura = precio promedio de ese
   mes, normalizada contra el máximo histórico global, no contra el mes visible, para que
   la comparación entre barras sea correcta a simple vista). El mes vigente se resalta en
   `brandIndigo`; los demás quedan en `lavenderMist`.
2. **Detalle del mes** (al tocar una barra) — hoja inferior con mínimo, máximo, promedio y
   número de observaciones de ese mes, más la lista de observaciones individuales con fecha.

Los meses sin observación real **no aparecen** en el gráfico — nunca se dibuja una barra en
cero para "rellenar" el calendario, porque una barra en cero es indistinguible de un precio
real de cero.

### 4.5 Listas de compra

El valor central de esta pantalla es responder **"¿cuánto me costaría esta compra, y dónde
puedo hacerla?"**, no simplemente listar productos. Dos decisiones sostienen esa respuesta:

- El estado de completitud de cada supermercado (cuántos ítems de la lista tiene con precio)
  se muestra como una etiqueta de advertencia visible cuando está incompleto, no como una
  nota pequeña fácil de ignorar — comparar el total de una tienda con 3 de 5 productos contra
  el total de una tienda con los 5 completos, sin marcar la diferencia, induciría a una
  decisión equivocada.
- **"Comprar distribuido"** (dividir la lista entre dos o más supermercados eligiendo el
  más barato por ítem) sólo se muestra cuando su total es **estrictamente menor** que el
  mejor total de una tienda completa. Si distribuir la compra no genera un ahorro real,
  ofrecerlo sería ruido, no ayuda.

### 4.6 Establecimientos

Con permiso de ubicación otorgado, la pantalla debe mostrar distancia y tiempo estimado a
pie, y permitir ordenar por cercanía; sin permiso, debe pedirlo con claridad. Nunca inventa
una distancia ni un establecimiento: mientras `physical_stores` no tenga datos reales
cargados, la pantalla lo declara explícitamente en vez de mostrar un estado ambiguo o
quedarse cargando indefinidamente (este último era, de hecho, un defecto real corregido en
el rediseño — ver `docs/ERS.md` §11.1).

### 4.7 Configuración

Muestra, por supermercado, si hay datos cargados y la fecha de su última actualización. Para
Carulla, Jumbo y Olímpica, el mensaje "sin datos todavía" es intencional y honesto: sus
scrapers existen pero no se han ejecutado por completo en este ambiente — no es un error de
la interfaz, es el estado real de los datos.

---

## 5. Referencias de estilo

El objetivo de composición declarado para el rediseño combina cuatro referencias de
industria, cada una aportando un principio concreto y no una copia literal de su interfaz:

- **Google Flights** — densidad de información ordenable sin saturar, usada como modelo
  para Resultados.
- **Apple (Human Interface Guidelines)** — jerarquía tipográfica clara y espaciado generoso,
  usada como modelo general de composición.
- **Airbnb** — tarjetas de producto con una sola pieza de información dominante (el precio)
  y el resto en segundo plano.
- **Linear** — uso disciplinado de un único color de acento sobre una base neutra, base de
  la regla 80/15/5 descrita en la sección 3.1.

---

## 6. Trazabilidad con el código

| Regla de este documento | Implementación |
|---|---|
| Paleta y tipografía | `mobile/lib/core/theme.dart` |
| Supermercados sin color propio | `mobile/lib/widgets/supermarket_badge.dart` |
| Orden en Resultados, sin filtro fijo | `mobile/lib/state/search_controller.dart` |
| Jerarquía y lenguaje del Detalle | `mobile/lib/screens/product_detail_screen.dart` |
| Barras mensuales + detalle del mes | `mobile/lib/screens/price_history_screen.dart` |
| Badge de incompletitud + compra distribuida | `mobile/lib/screens/shopping_list_detail_screen.dart` |
| Timeout de geolocalización | `mobile/lib/state/nearby_stores_controller.dart` |
| Estados de carga/vacío/error | `mobile/lib/widgets/state_views.dart` |
