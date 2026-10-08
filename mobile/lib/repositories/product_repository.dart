import '../models/basket.dart';
import '../models/compare_response.dart';
import '../models/price_history_monthly_response.dart';
import '../models/price_history_response.dart';
import '../models/product_detail.dart';
import '../models/product_list_response.dart';
import '../models/product_prices_response.dart';
import '../models/product_suggestion.dart';
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
    String? category,
    String? supermarket,
    String sort = 'price',
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{'page': '$page', 'limit': '$limit', 'sort': sort};
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (category != null && category.isNotEmpty) params['category'] = category;
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

  /// Sugerencias por similitud de texto (voz, OCR, o texto con errores) --
  /// nunca se usa para agregar un producto directamente, sólo para mostrar
  /// candidatos que el usuario debe confirmar.
  Future<ProductSuggestResponse> suggestProducts(
    String query, {
    int limit = 5,
    String prefer = 'comparable',
  }) async {
    final json = await _client.getJson(
      '/api/v1/products/suggest',
      queryParameters: {'q': query, 'limit': '$limit', 'prefer': prefer},
    );
    return ProductSuggestResponse.fromJson(json);
  }

  /// "¿Quisiste decir…?": búsqueda corregida si el texto parece mal escrito
  /// ("aroz" -> "arroz"), o null si está bien o no hay nada parecido.
  Future<String?> didYouMean(String query) async {
    final json = await _client.getJson(
      '/api/v1/products/did-you-mean',
      queryParameters: {'q': query},
    );
    return json['suggestion'] as String?;
  }

  /// Arma una lista para un nivel de gasto y, si se indica, un presupuesto.
  /// El orden de [terms] es su prioridad.
  Future<BasketResponse> buildBasket(
    List<String> terms, {
    required SpendTier tier,
    double? budget,
  }) async {
    final params = {'terms': terms.join('|'), 'tier': tier.apiValue};
    if (budget != null) params['budget'] = budget.round().toString();
    final json = await _client.getJson('/api/v1/products/basket', queryParameters: params);
    return BasketResponse.fromJson(json);
  }

  /// Lo que más se busca en la app (sólo texto y conteo, nada de la persona).
  Future<List<String>> popularSearches({int limit = 6}) async {
    final json = await _client.getJson(
      '/api/v1/products/popular-searches',
      queryParameters: {'limit': '$limit'},
    );
    return [
      for (final item in (json['items'] as List<dynamic>)) (item as Map<String, dynamic>)['term'] as String,
    ];
  }
}
