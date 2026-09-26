import '../models/category.dart';
import '../services/api_client.dart';

/// Acceso a `/api/v1/categories`.
class CategoryRepository {
  final ApiClient _client;

  CategoryRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<List<Category>> listCategories() async {
    final json = await _client.getJson('/api/v1/categories');
    return CategoryListResponse.fromJson(json).items;
  }
}
