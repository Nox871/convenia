import 'swap_suggestion.dart';

/// Espejo de `SingleStoreReplacement`: un producto de la lista que NO tiene este
/// supermercado y, si existe, el producto parecido de esa misma tienda que lo reemplaza.
class SingleStoreReplacement {
  final int itemId;
  final String itemName;
  final int quantity;
  final SwapAlternative? substitute;

  const SingleStoreReplacement({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.substitute,
  });

  factory SingleStoreReplacement.fromJson(Map<String, dynamic> json) => SingleStoreReplacement(
        itemId: json['item_id'] as int,
        itemName: json['item_name'] as String,
        quantity: json['quantity'] as int,
        substitute: json['substitute'] == null
            ? null
            : SwapAlternative.fromJson(json['substitute'] as Map<String, dynamic>),
      );
}

/// Espejo de `SingleStoreOption`: cómo quedaría la lista comprándola toda en un supermercado.
class SingleStoreOption {
  final String supermarketCode;
  final String supermarketName;
  final int itemsTotal;
  final int itemsPriced;
  final double currentTotal;
  final bool completable;
  final double? totalIfReplaced;
  final List<SingleStoreReplacement> replacements;

  const SingleStoreOption({
    required this.supermarketCode,
    required this.supermarketName,
    required this.itemsTotal,
    required this.itemsPriced,
    required this.currentTotal,
    required this.completable,
    required this.totalIfReplaced,
    required this.replacements,
  });

  /// Reemplazos que sí tienen un producto sustituto.
  List<SingleStoreReplacement> get applicable => [for (final r in replacements) if (r.substitute != null) r];

  /// Cuántos productos de la lista ya estarían resueltos (los que ya tiene + los reemplazables).
  int get coveredWithReplacements => itemsPriced + applicable.length;

  factory SingleStoreOption.fromJson(Map<String, dynamic> json) => SingleStoreOption(
        supermarketCode: json['supermarket_code'] as String,
        supermarketName: json['supermarket_name'] as String,
        itemsTotal: json['items_total'] as int,
        itemsPriced: json['items_priced'] as int,
        currentTotal: (json['current_total'] as num).toDouble(),
        completable: json['completable'] as bool,
        totalIfReplaced: (json['total_if_replaced'] as num?)?.toDouble(),
        replacements: (json['replacements'] as List<dynamic>? ?? const [])
            .map((e) => SingleStoreReplacement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
