/// Espejo de `app.schemas.product.ProductListItem`.
///
/// IMPORTANTE: hoy cada item representa UN `source_product` de UN solo
/// supermercado (el backend todavía no agrupa por producto canónico porque
/// `products`/`product_matches` están vacías). Por eso `price` es un único
/// valor y no un mapa por supermercado — no hay que inventar el precio del
/// otro supermercado si no viene en la respuesta.
class ProductListItem {
  final String id;
  final String name;
  final String? brand;
  final String? imageUrl;
  final String supermarketCode;
  final String supermarketName;
  final double? price;
  final double? listPrice;
  final String? currency;
  final bool isMatched;

  const ProductListItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.imageUrl,
    required this.supermarketCode,
    required this.supermarketName,
    required this.price,
    required this.listPrice,
    required this.currency,
    required this.isMatched,
  });

  factory ProductListItem.fromJson(Map<String, dynamic> json) {
    return ProductListItem(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      imageUrl: json['image_url'] as String?,
      supermarketCode: json['supermarket_code'] as String,
      supermarketName: json['supermarket_name'] as String,
      price: (json['price'] as num?)?.toDouble(),
      listPrice: (json['list_price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      isMatched: json['is_matched'] as bool? ?? false,
    );
  }
}
