import 'product_list_item.dart';

/// Espejo de `app.schemas.product.ProductSuggestion`/`ProductSuggestResponse`.
///
/// Resultado de la búsqueda tolerante a errores (`/products/suggest`), usada
/// cuando el texto no es exacto o es genérico: entrada por texto, voz o OCR.
/// Nunca se agrega un producto a una lista a partir de esto sin que el
/// usuario confirme cuál de las sugerencias es la correcta.
class ProductSuggestion {
  final String id;
  final String name;
  final String? brand;
  final double score;
  final String? imageUrl;
  final double? price;
  final int offersCount;

  const ProductSuggestion({
    required this.id,
    required this.name,
    required this.brand,
    required this.score,
    this.imageUrl,
    this.price,
    this.offersCount = 1,
  });

  /// Un producto elegido a mano (por ejemplo, desde el buscador) se trata igual
  /// que una propuesta del servidor.
  factory ProductSuggestion.fromListItem(ProductListItem item) => ProductSuggestion(
        id: item.id,
        name: item.name,
        brand: item.brand,
        score: 1,
        imageUrl: item.imageUrl,
        price: item.price,
        offersCount: item.offers.isNotEmpty ? item.offers.length : item.offersCount,
      );

  factory ProductSuggestion.fromJson(Map<String, dynamic> json) {
    return ProductSuggestion(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      score: (json['score'] as num).toDouble(),
      imageUrl: json['image_url'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      offersCount: json['offers_count'] as int? ?? 1,
    );
  }
}

class ProductSuggestResponse {
  final String query;
  final List<ProductSuggestion> suggestions;

  const ProductSuggestResponse({required this.query, required this.suggestions});

  factory ProductSuggestResponse.fromJson(Map<String, dynamic> json) {
    return ProductSuggestResponse(
      query: json['query'] as String,
      suggestions: (json['suggestions'] as List<dynamic>)
          .map((e) => ProductSuggestion.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
