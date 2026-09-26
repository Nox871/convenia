/// Espejo de `app.schemas.category.Category`.
class Category {
  final String label;
  final int productsCount;
  final List<String> supermarkets;

  const Category({required this.label, required this.productsCount, required this.supermarkets});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      label: json['label'] as String,
      productsCount: json['products_count'] as int,
      supermarkets: (json['supermarkets'] as List<dynamic>).cast<String>(),
    );
  }
}

class CategoryListResponse {
  final List<Category> items;

  const CategoryListResponse({required this.items});

  factory CategoryListResponse.fromJson(Map<String, dynamic> json) {
    return CategoryListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
