import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../core/device_id.dart';
import '../models/shopping_list.dart';
import '../repositories/shopping_list_repository.dart';
import 'view_status.dart';

/// Estado de la pantalla "Detalle de lista": ítems + costo por supermercado
/// (RF-LIST-002/003/004) + plan de compra distribuida cuando conviene.
class ShoppingListDetailController extends ChangeNotifier {
  final int listId;
  final ShoppingListRepository _repository;

  ShoppingListDetailController({required this.listId, ShoppingListRepository? repository})
    : _repository = repository ?? ShoppingListRepository() {
    _load();
  }

  ViewStatus status = ViewStatus.loading;
  String? errorMessage;
  ShoppingListDetail? detail;
  ShoppingListCostResponse? cost;
  ShoppingListDistributedResponse? distributedPlan;
  bool wasDeleted = false;

  /// Sólo tiene sentido ofrecer "comprar distribuido" cuando su total es
  /// ESTRICTAMENTE menor que el mejor total de una sola tienda COMPLETA --
  /// si no hay ahorro real, mostrarlo sería ruido, no ayuda a decidir.
  bool get distributedPlanWorthShowing {
    final plan = distributedPlan;
    final costs = cost?.costs;
    if (plan == null || plan.totalCost == null || costs == null) return false;
    final mejorCompleto = costs
        .where((c) => c.isComplete && c.totalCost != null)
        .map((c) => c.totalCost!)
        .fold<double?>(null, (min, v) => min == null || v < min ? v : min);
    if (mejorCompleto == null) return true; // ninguna tienda la tiene completa: distribuido es la única opción real
    return plan.totalCost! < mejorCompleto;
  }

  Future<void> retry() => _load();

  Future<void> _load() async {
    status = ViewStatus.loading;
    notifyListeners();

    try {
      final ownerRef = await DeviceId.get();
      final results = await Future.wait([
        _repository.getList(listId, ownerRef),
        _repository.getCost(listId, ownerRef),
        _repository.getDistributedPlan(listId, ownerRef),
      ]);
      detail = results[0] as ShoppingListDetail;
      cost = results[1] as ShoppingListCostResponse;
      distributedPlan = results[2] as ShoppingListDistributedResponse;
      status = ViewStatus.loaded;
    } on NotFoundException {
      status = ViewStatus.empty;
    } on ApiException catch (e) {
      status = ViewStatus.error;
      errorMessage = e.message;
    }

    notifyListeners();
  }

  Future<void> addItem(String productId) async {
    try {
      final ownerRef = await DeviceId.get();
      await _repository.addItem(listId, ownerRef, productId);
      await _refreshCostAndDetail(ownerRef);
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> updateQuantity(int itemId, int quantity) async {
    try {
      final ownerRef = await DeviceId.get();
      await _repository.updateItemQuantity(listId, itemId, ownerRef, quantity);
      await _refreshCostAndDetail(ownerRef);
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> removeItem(int itemId) async {
    try {
      final ownerRef = await DeviceId.get();
      await _repository.deleteItem(listId, itemId, ownerRef);
      await _refreshCostAndDetail(ownerRef);
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> rename(String name) async {
    try {
      final ownerRef = await DeviceId.get();
      detail = await _repository.renameList(listId, ownerRef, name);
      notifyListeners();
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> deleteList() async {
    try {
      final ownerRef = await DeviceId.get();
      await _repository.deleteList(listId, ownerRef);
      wasDeleted = true;
      notifyListeners();
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> _refreshCostAndDetail(String ownerRef) async {
    final results = await Future.wait([
      _repository.getList(listId, ownerRef),
      _repository.getCost(listId, ownerRef),
      _repository.getDistributedPlan(listId, ownerRef),
    ]);
    detail = results[0] as ShoppingListDetail;
    cost = results[1] as ShoppingListCostResponse;
    distributedPlan = results[2] as ShoppingListDistributedResponse;
    notifyListeners();
  }
}
