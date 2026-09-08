import '../models/shopping_list.dart';
import '../services/api_client.dart';

/// Acceso a `/api/v1/lists` (RF-LIST-001..004). `ownerRef` identifica el
/// dispositivo (ver `core/device_id.dart`) y se envía en cada llamada.
class ShoppingListRepository {
  final ApiClient _client;

  ShoppingListRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<List<ShoppingListSummary>> listLists(String ownerRef) async {
    final json = await _client.getJson('/api/v1/lists', queryParameters: {'owner_ref': ownerRef});
    return (json['items'] as List<dynamic>)
        .map((e) => ShoppingListSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ShoppingListDetail> createList(String ownerRef, String name) async {
    final json = await _client.postJson(
      '/api/v1/lists',
      body: {'owner_ref': ownerRef, 'name': name},
    );
    return ShoppingListDetail.fromJson(json);
  }

  Future<ShoppingListDetail> getList(int listId, String ownerRef) async {
    final json = await _client.getJson(
      '/api/v1/lists/$listId',
      queryParameters: {'owner_ref': ownerRef},
    );
    return ShoppingListDetail.fromJson(json);
  }

  Future<ShoppingListDetail> renameList(int listId, String ownerRef, String name) async {
    final json = await _client.putJson(
      '/api/v1/lists/$listId',
      body: {'name': name},
      queryParameters: {'owner_ref': ownerRef},
    );
    return ShoppingListDetail.fromJson(json);
  }

  Future<void> deleteList(int listId, String ownerRef) async {
    await _client.deleteNoContent(
      '/api/v1/lists/$listId',
      queryParameters: {'owner_ref': ownerRef},
    );
  }

  Future<ShoppingListDetail> addItem(
    int listId,
    String ownerRef,
    String productId, {
    int quantity = 1,
  }) async {
    final json = await _client.postJson(
      '/api/v1/lists/$listId/items',
      body: {'product_id': productId, 'quantity': quantity},
      queryParameters: {'owner_ref': ownerRef},
    );
    return ShoppingListDetail.fromJson(json);
  }

  Future<ShoppingListDetail> updateItemQuantity(
    int listId,
    int itemId,
    String ownerRef,
    int quantity,
  ) async {
    final json = await _client.putJson(
      '/api/v1/lists/$listId/items/$itemId',
      body: {'quantity': quantity},
      queryParameters: {'owner_ref': ownerRef},
    );
    return ShoppingListDetail.fromJson(json);
  }

  Future<ShoppingListDetail> deleteItem(int listId, int itemId, String ownerRef) async {
    final json = await _client.deleteJson(
      '/api/v1/lists/$listId/items/$itemId',
      queryParameters: {'owner_ref': ownerRef},
    );
    return ShoppingListDetail.fromJson(json);
  }

  Future<ShoppingListCostResponse> getCost(int listId, String ownerRef) async {
    final json = await _client.getJson(
      '/api/v1/lists/$listId/cost',
      queryParameters: {'owner_ref': ownerRef},
    );
    return ShoppingListCostResponse.fromJson(json);
  }

  Future<ShoppingListDistributedResponse> getDistributedPlan(int listId, String ownerRef) async {
    final json = await _client.getJson(
      '/api/v1/lists/$listId/cost/distributed',
      queryParameters: {'owner_ref': ownerRef},
    );
    return ShoppingListDistributedResponse.fromJson(json);
  }
}
