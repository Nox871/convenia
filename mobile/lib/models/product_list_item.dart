/// Espejo de `app.schemas.product.ProductListItem`.
///
/// Desde la Fase 2 del backend, un item puede representar:
/// - un producto AGRUPADO (`id` con prefijo "p-"): mejor precio entre los
///   supermercados donde ya está homologado, `offersCount > 1`,
///   `supermarketCode/supermarketName` en null (abarca varias tiendas).
/// - un producto SUELTO (`id` con prefijo "sp-"): todavía sin homologar,
///   `offersCount == 1`, con su única tienda real.
/// Nunca se inventa un precio ni una tienda para el otro caso.
/// Precio de un producto en un supermercado (item de `offers`).
class StoreOffer {
  final String supermarketCode;
  final String supermarketName;
  final double price;

  const StoreOffer({
    required this.supermarketCode,
    required this.supermarketName,
    required this.price,
  });

  factory StoreOffer.fromJson(Map<String, dynamic> json) => StoreOffer(
        supermarketCode: json['supermarket_code'] as String,
        supermarketName: json['supermarket_name'] as String,
        price: (json['price'] as num).toDouble(),
      );
}

class ProductListItem {
  final String id;
  final String name;
  final String? brand;
  final String? imageUrl;
  final String? supermarketCode;
  final String? supermarketName;
  final double? price;
  final double? listPrice;
  final String? currency;
  final int offersCount;
  final bool isMatched;

  /// Precio en cada supermercado al alcance, del más barato al más caro.
  final List<StoreOffer> offers;

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
    required this.offersCount,
    required this.isMatched,
    this.offers = const [],
  });

  factory ProductListItem.fromJson(Map<String, dynamic> json) {
    return ProductListItem(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      imageUrl: json['image_url'] as String?,
      supermarketCode: json['supermarket_code'] as String?,
      supermarketName: json['supermarket_name'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      listPrice: (json['list_price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      offersCount: json['offers_count'] as int? ?? 1,
      isMatched: json['is_matched'] as bool? ?? false,
      offers: [
        for (final o in (json['offers'] as List<dynamic>? ?? const []))
          StoreOffer.fromJson(o as Map<String, dynamic>),
      ],
    );
  }
}
