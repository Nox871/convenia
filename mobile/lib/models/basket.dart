import 'product_list_item.dart';

/// Nivel de gasto de una lista armada: cuánto se gasta por producto.
enum SpendTier {
  economico('economico', 'Económica', 'Lo más barato que encontramos'),
  medio('medio', 'Intermedia', 'Marcas conocidas a buen precio'),
  alto('alto', 'Completa', 'Marcas y presentaciones de gama alta');

  final String apiValue;
  final String label;
  final String description;

  const SpendTier(this.apiValue, this.label, this.description);

  /// Cuántos "$" se dibujan junto al nivel (1 a 3).
  int get dollars => index + 1;

  static SpendTier fromApi(String? value) =>
      SpendTier.values.firstWhere((t) => t.apiValue == value, orElse: () => SpendTier.medio);
}

/// Espejo de `app.schemas.product.BasketLine`.
class BasketLine {
  final String term;
  final bool found;
  final ProductListItem? product;
  final int quantity;
  final double subtotal;

  const BasketLine({
    required this.term,
    required this.found,
    required this.product,
    required this.quantity,
    required this.subtotal,
  });

  factory BasketLine.fromJson(Map<String, dynamic> json) {
    return BasketLine(
      term: json['term'] as String,
      found: json['found'] as bool,
      product: json['product'] == null
          ? null
          : ProductListItem.fromJson(json['product'] as Map<String, dynamic>),
      quantity: json['quantity'] as int? ?? 1,
      subtotal: (json['subtotal'] as num? ?? 0).toDouble(),
    );
  }
}

/// Espejo de `app.schemas.product.BasketResponse`.
class BasketResponse {
  final String tierRequested;
  final String tierUsed; // 'economico' | 'medio' | 'alto' | 'mixto'
  final double? budget;
  final double total;
  final double? remaining;
  final bool exceedsBudget;
  final List<String> droppedTerms;
  final List<BasketLine> items;

  const BasketResponse({
    required this.tierRequested,
    required this.tierUsed,
    required this.budget,
    required this.total,
    required this.remaining,
    required this.exceedsBudget,
    required this.droppedTerms,
    required this.items,
  });

  factory BasketResponse.fromJson(Map<String, dynamic> json) {
    return BasketResponse(
      tierRequested: json['tier_requested'] as String,
      tierUsed: json['tier_used'] as String,
      budget: (json['budget'] as num?)?.toDouble(),
      total: (json['total'] as num).toDouble(),
      remaining: (json['remaining'] as num?)?.toDouble(),
      exceedsBudget: json['exceeds_budget'] as bool? ?? false,
      droppedTerms: (json['dropped_terms'] as List<dynamic>? ?? const []).cast<String>(),
      items: (json['items'] as List<dynamic>)
          .map((e) => BasketLine.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
