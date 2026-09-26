import 'package:convenia_mobile/models/swap_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interpreta una sugerencia de cambio del backend', () {
    final swap = SwapSuggestion.fromJson({
      'item_id': 7,
      'item_name': 'Arroz DIANA blanco arroba (12500 gr)',
      'quantity': 2,
      'current_unit_price': 49900,
      'current_supermarket_name': 'Éxito',
      'alternative': {
        'product_id': 'sp-123',
        'name': 'Arroz EXITO MARCA PROPIA blanco arroba (12500 gr)',
        'brand': 'EXITO',
        'image_url': null,
        'unit_price': 40750.0,
        'supermarket_code': 'EXITO',
        'supermarket_name': 'Éxito',
      },
      'saving_total': 18300.0,
    });

    expect(swap.itemId, 7);
    expect(swap.quantity, 2);
    expect(swap.alternative.productId, 'sp-123');
    expect(swap.alternative.imageUrl, isNull);
    expect(swap.currentUnitPrice - swap.alternative.unitPrice, 9150);
    expect(swap.savingTotal, 18300);
  });
}
