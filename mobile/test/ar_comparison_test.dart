import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:convenia_mobile/core/barcode.dart';
import 'package:convenia_mobile/models/compare_response.dart';
import 'package:convenia_mobile/widgets/ar_comparison_card.dart';

/// Respuesta real de GET /api/v1/products/by-ean/7701362001614 (Café Juan Valdez),
/// con los precios de la base de Convenia al 3 de noviembre de 2026.
Map<String, dynamic> _json({bool stale = true}) {
  Map<String, dynamic> offer(String code, String name, double? price) => {
        'supermarket_code': code,
        'supermarket_name': name,
        'price': price,
        'list_price': price,
        'currency': price == null ? null : 'COP',
        'available': price == null ? null : true,
        'observed_at': price == null ? null : '2026-11-03T05:08:54Z',
        'payment_methods': [],
        'is_stale': price != null && stale,
      };
  final jumbo = offer('JUMBO', 'Jumbo', 35990);
  return {
    'product': {'id': 'p-10971', 'name': 'Café JUAN VALDEZ Huila edición especial navidad (220 gr)'},
    'offers': [
      offer('CARULLA', 'Carulla', 37300),
      offer('D1', 'D1', null),
      offer('EXITO', 'Éxito', 40250),
      jumbo,
      offer('OLIMPICA', 'Olímpica', null),
    ],
    'best_price': jumbo,
    'is_partial': true,
    'savings_absolute': 4260,
    'savings_percentage': 10.58,
  };
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('cleanBarcode', () {
    test('acepta EAN-13, EAN-8, UPC-12 y GTIN-14 y deja solo los dígitos', () {
      expect(cleanBarcode('7702025151585'), '7702025151585');
      expect(cleanBarcode('96385074'), '96385074');
      expect(cleanBarcode('012345678905'), '012345678905');
      expect(cleanBarcode('07622300722470'), '07622300722470');
      expect(cleanBarcode(' 770-2025-151585 '), '7702025151585');
    });

    test('rechaza lo que no es un código', () {
      expect(cleanBarcode(null), isNull);
      expect(cleanBarcode(''), isNull);
      expect(cleanBarcode('abc'), isNull);
      expect(cleanBarcode('12345'), isNull);
      expect(cleanBarcode('123456789012345'), isNull);
    });
  });

  group('ArComparisonCard', () {
    testWidgets('muestra el más barato, el ahorro y solo las tiendas con precio', (tester) async {
      await tester.pumpWidget(_wrap(ArComparisonCard(
        data: CompareResponse.fromJson(_json()),
        onAdd: () {},
        onClose: () {},
      )));

      expect(find.textContaining('Café JUAN VALDEZ'), findsOneWidget);
      expect(find.byKey(const Key('ar_best_price')), findsOneWidget);
      expect(find.text(r'$35.990'), findsWidgets);
      expect(find.textContaining('en Jumbo'), findsOneWidget);
      expect(find.byKey(const Key('ar_savings')), findsOneWidget);
      expect(find.textContaining(r'$4.260'), findsOneWidget);
      expect(find.textContaining('11 %'), findsOneWidget);
      // Éxito y Carulla tienen precio; D1 y Olímpica no, y no se inventan filas para ellas.
      expect(find.text('Éxito'), findsOneWidget);
      expect(find.text('Carulla'), findsOneWidget);
      expect(find.text('D1'), findsNothing);
      expect(find.text('Olímpica'), findsNothing);
    });

    testWidgets('avisa cuando los precios pueden estar desactualizados', (tester) async {
      await tester.pumpWidget(_wrap(ArComparisonCard(data: CompareResponse.fromJson(_json()), onAdd: () {}, onClose: () {})));
      expect(find.byKey(const Key('ar_stale')), findsOneWidget);

      await tester.pumpWidget(_wrap(ArComparisonCard(data: CompareResponse.fromJson(_json(stale: false)), onAdd: () {}, onClose: () {})));
      expect(find.byKey(const Key('ar_stale')), findsNothing);
    });

    testWidgets('sin precios no inventa un ahorro', (tester) async {
      final json = _json();
      json['offers'] = (json['offers'] as List).map((o) => {...(o as Map<String, dynamic>), 'price': null, 'is_stale': false}).toList();
      json['best_price'] = null;
      json['savings_absolute'] = null;
      json['savings_percentage'] = null;
      await tester.pumpWidget(_wrap(ArComparisonCard(data: CompareResponse.fromJson(json), onAdd: () {}, onClose: () {})));

      expect(find.text('Sin precios registrados para este producto.'), findsOneWidget);
      expect(find.byKey(const Key('ar_savings')), findsNothing);
    });

    testWidgets('los botones avisan a la pantalla', (tester) async {
      var added = 0, closed = 0;
      await tester.pumpWidget(_wrap(ArComparisonCard(
        data: CompareResponse.fromJson(_json()),
        onAdd: () => added++,
        onClose: () => closed++,
      )));
      await tester.tap(find.byKey(const Key('ar_add')));
      await tester.tap(find.byKey(const Key('ar_close')));
      expect([added, closed], [1, 1]);
    });
  });
}
