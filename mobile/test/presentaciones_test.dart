import 'package:convenia_mobile/core/spoken_list_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('presentaciones (huevos 30 und, café 500)', () {
    test('"huevos 30 und" es un solo producto con su presentación', () {
      final r = parseSpokenList('huevos 30 und');
      expect(r.length, 1);
      expect(r.first.searchText, 'huevos 30 und');
      expect(r.first.quantity, 1);
    });

    test('"30 unidades huevo" también es una presentación, no 30 compras', () {
      final r = parseSpokenList('30 unidades huevo');
      expect(r.length, 1);
      expect(r.first.quantity, 1);
      expect(r.first.searchText, 'huevo 30 und');
    });

    test('"café 500" se mantiene junto', () {
      final r = parseSpokenList('café 500');
      expect(r.length, 1);
      expect(r.first.searchText, 'café 500');
    });

    test('con coma y varios productos, cada uno conserva su presentación', () {
      final r = parseSpokenList('huevos 30 und, café 500, 2 leche');
      expect(r.map((e) => e.searchText), ['huevos 30 und', 'café 500', 'leche']);
      expect(r.map((e) => e.quantity), [1, 1, 2]);
    });

    test('"2 leche" sigue siendo cantidad 2 (menos de 10)', () {
      final r = parseSpokenList('2 leche');
      expect(r.first.quantity, 2);
    });
  });
}
