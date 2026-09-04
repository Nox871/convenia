import '../models/compare_response.dart';
import '../models/product_detail.dart';
import '../models/product_list_response.dart';
import '../models/product_prices_response.dart';
import '../services/api_client.dart';

/// Única puerta de entrada a los datos de producto para el resto de la app.
///
/// Envuelve [ApiClient] y traduce JSON crudo a modelos de dominio. Si en el
/// futuro el backend agrupa `/api/products` por producto canónico (cuando
/// exista homologación), solo este archivo debería necesitar ajustes.
class ProductRepository {
  final ApiClient _client;

  ProductRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<ProductListResponse> searchProducts({
    String? query,
    String? supermarket,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (supermarket != null && supermarket.isNotEmpty) params['supermarket'] = supermarket;

    final json = await _client.getJson('/api/products', queryParameters: params);
    return ProductListResponse.fromJson(json);
  }

  Future<ProductDetail> getProductDetail(String productId) async {
    final json = await _client.getJson('/api/products/$productId');
    return ProductDetail.fromJson(json);
  }

  Future<ProductPricesResponse> getProductPrices(String productId) async {
    final json = await _client.getJson('/api/products/$productId/prices');
    return ProductPricesResponse.fromJson(json);
  }

  Future<CompareResponse> compareProduct(String productId) async {
    final json = await _client.getJson('/api/products/$productId/compare');
    return CompareResponse.fromJson(json);
  }
}
