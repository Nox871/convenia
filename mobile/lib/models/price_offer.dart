/// Espejo de `app.schemas.price.PriceOffer`.
///
/// Los campos de precio son nulos cuando el supermercado no tiene oferta
/// para este producto: nunca se representa como precio 0, sino como
/// ausencia de dato — "Sin datos" en la UI.
class PriceOffer {
  final String supermarketCode;
  final String supermarketName;
  final double? price;
  final double? listPrice;
  final String? currency;
  final bool? available;
  final DateTime? observedAt;
  final List<Map<String, dynamic>> paymentMethods;
  final bool isStale;
  final double? unitPrice;
  final String? unitLabel;

  const PriceOffer({
    required this.supermarketCode,
    required this.supermarketName,
    required this.price,
    required this.listPrice,
    required this.currency,
    required this.available,
    required this.observedAt,
    required this.paymentMethods,
    this.isStale = false,
    this.unitPrice,
    this.unitLabel,
  });

  bool get hasData => price != null;

  factory PriceOffer.fromJson(Map<String, dynamic> json) {
    return PriceOffer(
      supermarketCode: json['supermarket_code'] as String,
      supermarketName: json['supermarket_name'] as String,
      price: (json['price'] as num?)?.toDouble(),
      listPrice: (json['list_price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      available: json['available'] as bool?,
      observedAt: json['observed_at'] == null
          ? null
          : DateTime.parse(json['observed_at'] as String),
      paymentMethods: (json['payment_methods'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>(),
      isStale: json['is_stale'] as bool? ?? false,
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      unitLabel: json['unit_label'] as String?,
    );
  }
}
