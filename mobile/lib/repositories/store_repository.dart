import '../models/coverage.dart';
import '../models/physical_store.dart';
import '../services/api_client.dart';

/// Acceso a `/api/v1/stores`.
class StoreRepository {
  final ApiClient _client;

  StoreRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<List<PhysicalStore>> listStores({String? supermarket}) async {
    final json = await _client.getJson(
      '/api/v1/stores',
      queryParameters: supermarket == null ? null : {'supermarket': supermarket},
    );
    return (json['items'] as List<dynamic>)
        .map((e) => PhysicalStore.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Qué supermercados tienen al menos una tienda dentro de `radiusKm`.
  Future<List<SupermarketCoverage>> getCoverage({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    final json = await _client.getJson(
      '/api/v1/stores/coverage',
      queryParameters: {'lat': '$latitude', 'lon': '$longitude', 'radius_km': '$radiusKm'},
    );
    return (json['supermarkets'] as List<dynamic>)
        .map((e) => SupermarketCoverage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<NearbyStore>> listStoresNearby({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
  }) async {
    final json = await _client.getJson(
      '/api/v1/stores/nearby',
      queryParameters: {
        'lat': '$latitude',
        'lon': '$longitude',
        'radius_km': '$radiusKm',
        'limit': '50',
      },
    );
    return (json['items'] as List<dynamic>)
        .map((e) => NearbyStore.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Alta manual de un establecimiento -- sólo administradores (el backend
  /// responde 403 si el token no tiene ese rol).
  Future<PhysicalStore> createStore({
    required String supermarketCode,
    required String name,
    String? address,
    String? city,
    required double latitude,
    required double longitude,
  }) async {
    final json = await _client.postJson(
      '/api/v1/stores',
      body: {
        'supermarket_code': supermarketCode,
        'name': name,
        'address': address,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return PhysicalStore.fromJson(json);
  }
}
