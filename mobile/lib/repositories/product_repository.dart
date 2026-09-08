import '../models/compare_response.dart';
import '../models/price_history_monthly_response.dart';
import '../models/price_history_response.dart';
import '../models/product_detail.dart';
import '../models/product_list_response.dart';
import '../models/product_prices_response.dart';
import '../services/api_client.dart';

/// Única puerta de entrada a los datos de producto para el resto de la app.
///
/// Envuelve [ApiClient] y traduce JSON crudo a modelos de dominio. Si en el
/// futuro el backend agrupa `/api/v1/products` por producto canónico (cuando
/// exista homologación), solo este archivo debería necesitar ajustes.
class ProductRepository {
  final ApiClient _client;

  ProductRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<ProductListResponse> searchProducts({
    String? query,
    String? supermarket,
    String sort = 'price',
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{'page': '$page', 'limit': '$limit', 'sort': sort};
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (supermarket != null && supermarket.isNotEmpty) params['supermarket'] = supermarket;

    final json = await _client.getJson('/api/v1/products', queryParameters: params);
    return ProductListResponse.fromJson(json);
  }

  Future<ProductDetail> getProductDetail(String productId) async {
    final json = await _client.getJson('/api/v1/products/$productId');
    return ProductDetail.fromJson(json);
  }

  Future<ProductPricesResponse> getProductPrices(String productId) async {
    final json = await _client.getJson('/api/v1/products/$productId/prices');
    return ProductPricesResponse.fromJson(json);
  }

  Future<CompareResponse> compareProduct(String productId) async {
    final json = await _client.getJson('/api/v1/products/$productId/compare');
    return CompareResponse.fromJson(json);
  }

  Future<PriceHistoryResponse> getPriceHistory(
    String productId, {
    int page = 1,
    int limit = 20,
    String? month,
  }) async {
    final params = {'page': '$page', 'limit': '$limit'};
    if (month != null) params['month'] = month;
    final json = await _client.getJson(
      '/api/v1/products/$productId/history',
      queryParameters: params,
    );
    return PriceHistoryResponse.fromJson(json);
  }

  Future<PriceHistoryMonthlyResponse> getPriceHistoryMonthly(String productId) async {
    final json = await _client.getJson('/api/v1/products/$productId/history/monthly');
    return PriceHistoryMonthlyResponse.fromJson(json);
  }
}
