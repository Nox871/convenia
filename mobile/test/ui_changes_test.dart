import 'dart:io';
import 'dart:ui' as ui;

import 'package:convenia_mobile/core/travel_mode.dart';
import 'package:convenia_mobile/models/product_list_item.dart';
import 'package:convenia_mobile/widgets/create_list_sheet.dart';
import 'package:convenia_mobile/widgets/product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

ProductListItem _item({List<StoreOffer> offers = const [], double? list, String? brand = 'Diana'}) =>
    ProductListItem(
      id: 'p-1',
      name: 'Arroz DIANA blanco vitamor (500 gr)',
      brand: brand,
      imageUrl: null,
      supermarketCode: null,
      supermarketName: null,
      price: offers.isEmpty ? 1990 : offers.first.price,
      listPrice: list,
      currency: 'COP',
      offersCount: offers.length,
      isMatched: offers.length > 1,
      offers: offers,
    );

const _ofertas = [
  StoreOffer(supermarketCode: 'EXITO', supermarketName: 'Éxito', price: 1490),
  StoreOffer(supermarketCode: 'JUMBO', supermarketName: 'Jumbo', price: 1990),
];

void main() {
  group('TravelMode', () {
    test('tiempos coherentes: a pie > bici > carro > moto para la misma distancia', () {
      const km = 2.0;
      expect(TravelMode.walking.minutesFor(km), 30); // 2 × 1,25 / 5 km/h
      expect(TravelMode.bicycle.minutesFor(km), 10);
      expect(TravelMode.car.minutesFor(km), 8);
      expect(TravelMode.motorbike.minutesFor(km), 6);
    });

    test('nunca da 0 minutos y formatea horas', () {
      expect(TravelMode.car.minutesFor(0.05), 1);
      expect(TravelMode.walking.durationLabel(0.1), '2 min');
      expect(TravelMode.walking.durationLabel(6), '1 h 30 min');
      expect(TravelMode.walking.durationLabel(4), '1 h');
    });

    test('se recupera por nombre y cae a pie si no se reconoce', () {
      expect(TravelMode.fromName('car'), TravelMode.car);
      expect(TravelMode.fromName('nada'), TravelMode.walking);
      expect(TravelMode.fromName(null), TravelMode.walking);
    });

    test('Google Maps: moto y bici tienen su propio modo', () {
      expect(TravelMode.motorbike.googleMode, 'two-wheeler');
      expect(TravelMode.bicycle.googleMode, 'bicycling');
    });
  });

  group('ProductCard', () {
    Future<void> pump(WidgetTester tester, ProductListItem item, {GlobalKey? key}) async {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFF7F5EF),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(key: key, child: ProductCard(item: item, onTap: () {})),
          ),
        ),
      ));
    }

    testWidgets('las etiquetas llevan solo el nombre de la tienda, no el precio', (tester) async {
      await pump(tester, _item(offers: _ofertas));
      expect(find.text('Éxito'), findsOneWidget);
      expect(find.text('Jumbo'), findsOneWidget);
      expect(find.textContaining(r'Éxito $'), findsNothing);
      expect(find.textContaining(r'Jumbo $'), findsNothing);
      // el precio aparece una sola vez
      expect(find.text(r'Desde $1.490'), findsOneWidget);
    });

    testWidgets('una sola tienda: precio sin "Desde" y una etiqueta', (tester) async {
      await pump(tester, _item(offers: const [
        StoreOffer(supermarketCode: 'D1', supermarketName: 'D1', price: 6300),
      ]));
      expect(find.text(r'$6.300'), findsOneWidget);
      expect(find.text('D1'), findsOneWidget);
    });

    testWidgets('el precio tachado va en rojo', (tester) async {
      await pump(tester, _item(offers: _ofertas, list: 1900));
      final tachado = tester.widget<Text>(find.text(r'$1.900'));
      expect(tachado.style!.decoration, TextDecoration.lineThrough);
      expect(tachado.style!.color, const Color(0xFFC94A4A));
    });

    testWidgets('orden: marca, título, precio (con el anterior chico arriba a la derecha), tags', (tester) async {
      await pump(tester, _item(offers: _ofertas, list: 1900));
      Offset pos(Finder f) => tester.getTopLeft(f);

      final marca = pos(find.text('DIANA'));
      final titulo = pos(find.text('Arroz DIANA blanco vitamor (500 gr)'));
      final precio = pos(find.text(r'Desde $1.490'));
      final anterior = pos(find.text(r'$1.900'));
      final tag = pos(find.text('Éxito'));

      expect(marca.dy, lessThan(titulo.dy));
      expect(titulo.dy, lessThan(precio.dy));
      expect(precio.dy, lessThan(tag.dy));

      // el precio anterior va a la DERECHA del precio real y arriba (superíndice)
      expect(anterior.dx, greaterThan(precio.dx));
      expect(anterior.dy, lessThanOrEqualTo(precio.dy + 4));

      // y es más chico que el precio real: no compite con él
      final tAnterior = tester.widget<Text>(find.text(r'$1.900')).style!.fontSize!;
      final alturaPrecio = tester.getSize(find.text(r'Desde $1.490')).height;
      final alturaAnterior = tester.getSize(find.text(r'$1.900')).height;
      expect(tAnterior, lessThan(12));
      expect(alturaAnterior, lessThan(alturaPrecio));
    });

    testWidgets('"Sin marca" no ocupa una línea', (tester) async {
      await pump(tester, _item(offers: _ofertas, brand: 'Sin marca'));
      expect(find.text('SIN MARCA'), findsNothing);
    });

    testWidgets('marca vacía no deja un hueco', (tester) async {
      await pump(tester, _item(offers: _ofertas, brand: null));
      expect(tester.takeException(), isNull);
    });

    testWidgets('render para revisar la distribución', (tester) async {
      final key = GlobalKey();
      await pump(tester, _item(offers: _ofertas, list: 1900), key: key);
      final dir = Platform.environment['CHART_OUT'];
      if (dir == null) return;
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/tarjeta.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    });
  });

  group('Hoja de nueva lista', () {
    testWidgets('Crear está deshabilitado sin nombre, y una idea lo rellena', (tester) async {
      String? resultado;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => resultado = await showCreateListSheet(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final crear = find.widgetWithText(ElevatedButton, 'Crear lista');
      expect(tester.widget<ElevatedButton>(crear).onPressed, isNull);

      await tester.tap(find.text('Aseo del hogar'));
      await tester.pump();
      expect(tester.widget<ElevatedButton>(crear).onPressed, isNotNull);

      await tester.tap(crear);
      await tester.pumpAndSettle();
      expect(resultado, 'Aseo del hogar');
    });

    testWidgets('Cancelar devuelve null y queda a la izquierda de Crear', (tester) async {
      String? resultado = 'sin tocar';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => resultado = await showCreateListSheet(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final cancelar = tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Cancelar'));
      final crear = tester.getTopLeft(find.widgetWithText(ElevatedButton, 'Crear lista'));
      expect(cancelar.dx, lessThan(crear.dx)); // lado a lado, no uno encima del otro
      expect((cancelar.dy - crear.dy).abs(), lessThan(1));

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(resultado, isNull);
    });
  });
}
