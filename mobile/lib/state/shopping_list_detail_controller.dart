import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../core/budget.dart';
import '../core/device_id.dart';
import '../models/shopping_list.dart';
import '../models/swap_suggestion.dart';
import '../repositories/shopping_list_repository.dart';
import 'view_status.dart';

/// Estado de la pantalla "Detalle de lista": ítems, costo por supermercado
/// y plan de compra distribuida cuando conviene.
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

  /// Cambios sugeridos para bajar el costo; sólo se piden cuando la lista se
  /// pasa del presupuesto.
  List<SwapSuggestion> swaps = [];

  /// Cómo va la lista contra su presupuesto (contra el total completo de un
  /// supermercado o, si no hay, el repartido), o `null` si no hay cómo comparar.
  BudgetComparison? get budgetComparison {
    final budget = detail?.budget;
    final costs = cost;
    if (budget == null || costs == null) return null;
    return compareToBudget(budget, completeListTotal(costs)) ??
        compareToBudget(budget, distributedTotal(distributedPlan));
  }

  bool get isOverBudget => budgetComparison != null && !budgetComparison!.isWithin;

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
      await _loadSwaps(ownerRef);
    } on NotFoundException {
      status = ViewStatus.empty;
    } on ApiException catch (e) {
      status = ViewStatus.error;
      errorMessage = e.message;
    }

    notifyListeners();
  }

  Future<bool> addItem(String productId, {int quantity = 1}) async {
    try {
      final ownerRef = await DeviceId.get();
      await _repository.addItem(listId, ownerRef, productId, quantity: quantity);
      await _refreshCostAndDetail(ownerRef);
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
      return false;
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

  Future<void> setBudget(int? budget) async {
    try {
      final ownerRef = await DeviceId.get();
      detail = await _repository.setBudget(listId, ownerRef, budget);
      await _loadSwaps(ownerRef);
      notifyListeners();
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
    await _loadSwaps(ownerRef);
    notifyListeners();
  }

  /// Pide los cambios sugeridos sólo si la lista se pasa del presupuesto. Es
  /// una ayuda opcional: si falla, simplemente no se muestran.
  Future<void> _loadSwaps(String ownerRef) async {
    if (!isOverBudget) {
      swaps = [];
      return;
    }
    try {
      swaps = await _repository.getSwapSuggestions(listId, ownerRef);
    } catch (_) {
      swaps = [];
    }
  }

  /// Aplica un cambio sugerido: agrega el sustituto con la misma cantidad y
  /// quita el producto original.
  Future<bool> applySwap(SwapSuggestion swap) async {
    final added = await addItem(swap.alternative.productId, quantity: swap.quantity);
    if (!added) return false;
    await removeItem(swap.itemId);
    return true;
  }
}
