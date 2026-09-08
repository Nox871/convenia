import '../models/supermarket.dart';
import '../services/api_client.dart';

/// Acceso a `/api/v1/supermarkets`.
class SupermarketRepository {
  final ApiClient _client;

  SupermarketRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<List<Supermarket>> listSupermarkets() async {
    final json = await _client.getJson('/api/v1/supermarkets');
    return (json['items'] as List<dynamic>)
        .map((e) => Supermarket.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
