/// Espejo de `app.schemas.price.PriceOffer`.
class PriceOffer {
  final String supermarketCode;
  final String supermarketName;
  final double price;
  final double? listPrice;
  final String currency;
  final bool available;
  final DateTime observedAt;
  final List<Map<String, dynamic>> paymentMethods;

  const PriceOffer({
    required this.supermarketCode,
    required this.supermarketName,
    required this.price,
    required this.listPrice,
    required this.currency,
    required this.available,
    required this.observedAt,
    required this.paymentMethods,
  });

  factory PriceOffer.fromJson(Map<String, dynamic> json) {
    return PriceOffer(
      supermarketCode: json['supermarket_code'] as String,
      supermarketName: json['supermarket_name'] as String,
      price: (json['price'] as num).toDouble(),
      listPrice: (json['list_price'] as num?)?.toDouble(),
      currency: json['currency'] as String,
      available: json['available'] as bool,
      observedAt: DateTime.parse(json['observed_at'] as String),
      paymentMethods: (json['payment_methods'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>(),
    );
  }
}
