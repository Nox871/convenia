import '../models/swap_suggestion.dart';
import '../models/shopping_list.dart';
import '../services/api_client.dart';

/// Acceso a `/api/v1/lists`. `ownerRef` identifica el dispositivo (ver
/// `core/device_id.dart`) y se envía en cada llamada.
class ShoppingListRepository {
  final ApiClient _client;

  ShoppingListRepository({ApiClient? client}) : _client = client ?? ApiClient();

  /// Pasa a la cuenta con sesión iniciada las listas que se hicieron en este
  /// dispositivo como invitado. Devuelve cuántas pasaron.
  Future<int> claimDeviceLists(String deviceRef) async {
    final json = await _client.postJson('/api/v1/lists/claim', body: {'owner_ref': deviceRef});
    return json['claimed'] as int;
  }

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

  /// Fija el presupuesto de la lista (en pesos), o lo quita con `null`.
  Future<ShoppingListDetail> setBudget(int listId, String ownerRef, int? budget) async {
    final json = await _client.putJson(
      '/api/v1/lists/$listId/budget',
      body: {'budget': budget},
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

  /// Cambios que bajarían el costo de la lista (sustitutos del mismo tipo y
  /// tamaño, más baratos).
  Future<List<SwapSuggestion>> getSwapSuggestions(int listId, String ownerRef) async {
    final json = await _client.getJson(
      '/api/v1/lists/$listId/savings',
      queryParameters: {'owner_ref': ownerRef},
    );
    return (json['suggestions'] as List<dynamic>)
        .map((e) => SwapSuggestion.fromJson(e as Map<String, dynamic>))
        .toList();
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
