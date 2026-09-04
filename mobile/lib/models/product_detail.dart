/// Espejo de `app.schemas.product.ProductDetail`.
class ProductDetail {
  final String id;
  final String name;
  final String? brand;
  final String? category;
  final String? imageUrl;
  final String? productUrl;
  final bool isMatched;
  final int offersCount;
  final List<String> supermarkets;

  const ProductDetail({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.imageUrl,
    required this.productUrl,
    required this.isMatched,
    required this.offersCount,
    required this.supermarkets,
  });

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    return ProductDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      category: json['category'] as String?,
      imageUrl: json['image_url'] as String?,
      productUrl: json['product_url'] as String?,
      isMatched: json['is_matched'] as bool,
      offersCount: json['offers_count'] as int,
      supermarkets: (json['supermarkets'] as List<dynamic>).cast<String>(),
    );
  }
}
