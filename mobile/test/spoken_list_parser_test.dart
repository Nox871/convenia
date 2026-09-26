import 'package:convenia_mobile/core/spoken_list_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSpokenList', () {
    test('separa una frase conversacional en varios ítems con cantidad', () {
      final result = parseSpokenList(
        'me gustaría comprar 12 huevos, un litro de agua y dos bolsas de arroz',
      );

      expect(result.map((e) => e.searchText).toList(), ['huevos', 'agua', 'arroz']);
      expect(result.map((e) => e.quantity).toList(), [12, 1, 2]);
    });

    test('asume cantidad 1 cuando no se dice ninguna', () {
      final result = parseSpokenList('quiero café y leche');

      expect(result.map((e) => e.searchText).toList(), ['café', 'leche']);
      expect(result.every((e) => e.quantity == 1), isTrue);
    });

    test('reconoce números escritos en palabras, con o sin tilde', () {
      final result = parseSpokenList('dieciséis manzanas, tres jabones');

      expect(result[0].quantity, 16);
      expect(result[1].quantity, 3);
    });

    test('descarta envases y unidades del texto de búsqueda', () {
      final result = parseSpokenList('dos paquetes de galletas');

      expect(result.single.searchText, 'galletas');
      expect(result.single.quantity, 2);
    });

    test('separa también por líneas (una por producto, como sale del OCR)', () {
      final result = parseSpokenList('arroz\nleche\n2 huevos');

      expect(result.map((e) => e.searchText).toList(), ['arroz', 'leche', 'huevos']);
      expect(result.map((e) => e.quantity).toList(), [1, 1, 2]);
    });

    test('lenguaje cotidiano: una lista de términos genéricos', () {
      final result = parseSpokenList('debo comprar arroz, leche, huevos, aguacate');

      expect(result.map((e) => e.searchText).toList(), ['arroz', 'leche', 'huevos', 'aguacate']);
    });

    test('devuelve lista vacía con texto vacío o solo relleno', () {
      expect(parseSpokenList(''), isEmpty);
      expect(parseSpokenList('   '), isEmpty);
      expect(parseSpokenList('quiero comprar'), isEmpty);
    });
  });
}
