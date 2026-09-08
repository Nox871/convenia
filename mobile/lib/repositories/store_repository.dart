import '../models/physical_store.dart';
import '../services/api_client.dart';

/// Acceso a `/api/v1/stores` (ERS §17).
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
      },
    );
    return (json['items'] as List<dynamic>)
        .map((e) => NearbyStore.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
