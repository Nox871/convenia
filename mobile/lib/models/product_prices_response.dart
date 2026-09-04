import 'price_offer.dart';

/// Espejo de `app.schemas.price.ProductPricesResponse`.
class ProductPricesResponse {
  final String productId;
  final List<PriceOffer> offers;

  const ProductPricesResponse({required this.productId, required this.offers});

  factory ProductPricesResponse.fromJson(Map<String, dynamic> json) {
    return ProductPricesResponse(
      productId: json['product_id'] as String,
      offers: (json['offers'] as List<dynamic>)
          .map((e) => PriceOffer.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
