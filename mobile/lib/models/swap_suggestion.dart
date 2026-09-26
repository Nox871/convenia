/// Espejo de `app.schemas.shopping_list.SwapAlternative`.
class SwapAlternative {
  final String productId;
  final String name;
  final String? brand;
  final String? imageUrl;
  final double unitPrice;
  final String supermarketCode;
  final String supermarketName;

  const SwapAlternative({
    required this.productId,
    required this.name,
    required this.brand,
    required this.imageUrl,
    required this.unitPrice,
    required this.supermarketCode,
    required this.supermarketName,
  });

  factory SwapAlternative.fromJson(Map<String, dynamic> json) {
    return SwapAlternative(
      productId: json['product_id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      imageUrl: json['image_url'] as String?,
      unitPrice: (json['unit_price'] as num).toDouble(),
      supermarketCode: json['supermarket_code'] as String,
      supermarketName: json['supermarket_name'] as String,
    );
  }
}

/// Espejo de `SwapSuggestion`: cambiar un ítem de la lista por un producto del
/// mismo tipo y tamaño que es más barato.
class SwapSuggestion {
  final int itemId;
  final String itemName;
  final int quantity;
  final double currentUnitPrice;
  final String currentSupermarketName;
  final SwapAlternative alternative;
  final double savingTotal;

  const SwapSuggestion({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.currentUnitPrice,
    required this.currentSupermarketName,
    required this.alternative,
    required this.savingTotal,
  });

  factory SwapSuggestion.fromJson(Map<String, dynamic> json) {
    return SwapSuggestion(
      itemId: json['item_id'] as int,
      itemName: json['item_name'] as String,
      quantity: json['quantity'] as int,
      currentUnitPrice: (json['current_unit_price'] as num).toDouble(),
      currentSupermarketName: json['current_supermarket_name'] as String,
      alternative: SwapAlternative.fromJson(json['alternative'] as Map<String, dynamic>),
      savingTotal: (json['saving_total'] as num).toDouble(),
    );
  }
}
