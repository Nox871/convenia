import 'package:convenia_mobile/core/spoken_list_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _terms(String text) => parseSpokenList(text).map((e) => e.searchText).toList();
List<int> _quantities(String text) => parseSpokenList(text).map((e) => e.quantity).toList();

/// Los reconocedores de voz no ponen comas: "arroz, leche, huevos" llega como
/// "arroz leche huevos".
void main() {
  group('lista dicha sin comas', () {
    test('varios productos seguidos se separan', () {
      expect(_terms('arroz leche huevos aguacate'), ['arroz', 'leche', 'huevos', 'aguacate']);
    });

    test('el ejemplo del usuario: "debo comprar arroz leche huevos aguacate"', () {
      expect(_terms('debo comprar arroz leche huevos aguacate'), ['arroz', 'leche', 'huevos', 'aguacate']);
    });

    test('cantidades entre productos abren un ítem nuevo', () {
      expect(_terms('2 leche 3 huevos'), ['leche', 'huevos']);
      expect(_quantities('2 leche 3 huevos'), [2, 3]);
      expect(_terms('arroz 2 leche'), ['arroz', 'leche']);
      expect(_quantities('arroz 2 leche'), [1, 2]);
    });

    test('un nombre compuesto no se parte', () {
      expect(_terms('leche entera'), ['leche entera']);
      expect(_terms('queso crema'), ['queso crema']);
      expect(_terms('pan tajado'), ['pan tajado']);
    });

    test('lo que va tras "de", "con", "sin" o "para" es parte del mismo producto', () {
      expect(_terms('leche de coco'), ['leche coco']);
      expect(_terms('arroz con pollo'), ['arroz con pollo']);
      expect(_terms('aceite para freir'), ['aceite para freir']);
      expect(_terms('salsa de tomate'), ['salsa tomate']);
    });

    test('un tamaño no es una cantidad nueva', () {
      expect(_terms('leche 900 ml'), ['leche 900 ml']);
      expect(_quantities('leche 900 ml'), [1]);
    });

    test('mezcla de comas y corridos', () {
      expect(_terms('arroz leche, huevos aguacate y pan'), ['arroz', 'leche', 'huevos', 'aguacate', 'pan']);
    });

    test('un solo producto no cambia', () {
      expect(_terms('arroz'), ['arroz']);
      expect(_terms('dos bolsas de arroz'), ['arroz']);
      expect(_quantities('dos bolsas de arroz'), [2]);
    });
  });
}
