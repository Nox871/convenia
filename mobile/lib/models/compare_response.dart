import 'price_offer.dart';

/// Espejo de `app.schemas.price.ProductRef`.
class ProductRefLite {
  final String id;
  final String name;

  const ProductRefLite({required this.id, required this.name});

  factory ProductRefLite.fromJson(Map<String, dynamic> json) {
    return ProductRefLite(id: json['id'] as String, name: json['name'] as String);
  }
}

/// Espejo de `app.schemas.price.CompareResponse`.
class CompareResponse {
  final ProductRefLite product;
  final List<PriceOffer> offers;
  final PriceOffer? bestPrice;

  const CompareResponse({required this.product, required this.offers, required this.bestPrice});

  factory CompareResponse.fromJson(Map<String, dynamic> json) {
    return CompareResponse(
      product: ProductRefLite.fromJson(json['product'] as Map<String, dynamic>),
      offers: (json['offers'] as List<dynamic>)
          .map((e) => PriceOffer.fromJson(e as Map<String, dynamic>))
          .toList(),
      bestPrice: json['best_price'] == null
          ? null
          : PriceOffer.fromJson(json['best_price'] as Map<String, dynamic>),
    );
  }
}
