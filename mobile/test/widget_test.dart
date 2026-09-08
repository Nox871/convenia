// Smoke test: verifica que la app arranca en Home con los textos clave de
// la especificación visual, sin depender del backend (Home no hace
// llamadas HTTP hasta que el usuario busca algo).

import 'package:flutter_test/flutter_test.dart';

import 'package:convenia_mobile/main.dart';

void main() {
  testWidgets('Home muestra el logo, el título y el buscador', (WidgetTester tester) async {
    await tester.pumpWidget(const ConveniaApp());

    expect(find.text('Convenia'), findsOneWidget);
    expect(find.text('Encuentra dónde te conviene comprar'), findsOneWidget);
    expect(find.text('¿Qué producto estás buscando?'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);

    // Búsquedas frecuentes.
    expect(find.text('Leche'), findsOneWidget);
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Café'), findsOneWidget);
    expect(find.text('Huevos'), findsOneWidget);
  });
}

// Nota: no se agrega aquí una prueba que navegue a Resultados, porque esa
// pantalla dispara una llamada HTTP real al backend desde el constructor de
// `SearchResultsController` — en un `flutter test` (sin emulador ni
// backend) eso sería una prueba de red flaky, no una prueba unitaria/widget
// real. Cubrir Resultados/Detalle con pruebas aisladas requeriría inyectar
// un `ProductRepository` de prueba (ya soportado por el parámetro opcional
// `repository` de ambos controllers), lo cual queda fuera de esta primera
// versión de tests.
