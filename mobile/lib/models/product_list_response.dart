import 'page_info.dart';
import 'product_list_item.dart';

/// Espejo de `app.schemas.product.ProductListResponse`.
class ProductListResponse {
  final List<ProductListItem> items;
  final PageInfo pagination;

  const ProductListResponse({required this.items, required this.pagination});

  factory ProductListResponse.fromJson(Map<String, dynamic> json) {
    return ProductListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => ProductListItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      pagination: PageInfo.fromJson(json['pagination'] as Map<String, dynamic>),
    );
  }
}
