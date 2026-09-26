import 'package:convenia_mobile/core/ocr_list_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quita viñetas y numeración', () {
    expect(
      cleanOcrLines('- arroz\n• leche\n☐ huevos\n1. pan\n2) aguacate\n[ ] cafe'),
      ['arroz', 'leche', 'huevos', 'pan', 'aguacate', 'cafe'],
    );
  });

  test('conserva la cantidad al inicio de la línea', () {
    expect(cleanOcrLines('2 leche\n12 huevos'), ['2 leche', '12 huevos']);
  });

  test('quita precios al final pero no números del nombre', () {
    expect(
      cleanOcrLines('Arroz Diana 5.200\nLeche entera \$3.770\nAgua 600 ml'),
      ['Arroz Diana', 'Leche entera', 'Agua 600 ml'],
    );
  });

  test('descarta encabezados, líneas sólo numéricas y ruido', () {
    expect(
      cleanOcrLines('Lista de compras\n\n12\n\$ 5.000\n-\nMercado:\nqueso'),
      ['queso'],
    );
  });

  test('un texto vacío o sin letras no da líneas', () {
    expect(cleanOcrLines(''), isEmpty);
    expect(cleanOcrLines('123\n456 789'), isEmpty);
  });
}
