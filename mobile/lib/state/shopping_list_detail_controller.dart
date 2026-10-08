import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../core/budget.dart';
import '../core/device_id.dart';
import '../models/shopping_list.dart';
import '../models/single_store.dart';
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

  /// Cuándo se guardó el último cambio. Las listas se guardan solas, en el
  /// servidor, apenas se hace cada cambio; esto sólo lo hace visible.
  DateTime? savedAt;

  /// En qué supermercado conviene comprar cada producto de la lista (el de
  /// menor precio) y cuánto cuesta, según el plan repartido.
  Map<int, ({String store, double subtotal})> get assignments {
    final plan = distributedPlan;
    if (plan == null) return const {};
    return {
      for (final stop in plan.stops)
        for (final item in stop.items) item.itemId: (store: stop.supermarketName, subtotal: item.subtotal),
    };
  }

  /// El cierre de la lista ("Listo"): lo que más sirve saber al terminar, en una
  /// frase. Es el momento que la persona recuerda, así que lleva el resultado
  /// bueno (dónde comprar y cuánto) y no sólo "guardado".
  String finishSummary() {
    final name = detail?.name ?? 'Tu lista';
    final items = detail?.items.length ?? 0;
    if (items == 0) return '«$name» guardada';
    final costs = cost?.costs ?? const <SupermarketCost>[];
    final best = costs.where((c) => c.supermarketCode == cost?.bestSupermarketCode).firstOrNull;
    if (best?.totalCost != null) {
      return '«$name» guardada · comprándola en ${best!.supermarketName}: ${_pesos(best.totalCost!)}';
    }
    final plan = distributedPlan;
    if (plan?.totalCost != null && plan!.stops.length > 1) {
      return '«$name» guardada · repartida en ${plan.stops.length} supermercados: ${_pesos(plan.totalCost!)}';
    }
    return '«$name» guardada · $items ${items == 1 ? 'producto' : 'productos'}';
  }

  static String _pesos(double v) {
    final digits = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return '\$$buf';
  }

  /// Ids de productos que no tienen precio en ningún supermercado al alcance.
  Set<int> get unpricedItemIds => (distributedPlan?.unpricedItemIds ?? const <int>[]).toSet();

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
      savedAt = DateTime.now();
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
      savedAt = DateTime.now();
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
    savedAt = DateTime.now();
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

  /// Opciones para comprar la lista en un solo supermercado. Se piden sólo cuando la
  /// persona las abre (es un cálculo más pesado que el resto de la pantalla).
  Future<List<SingleStoreOption>> loadSingleStoreOptions() async {
    final ownerRef = await DeviceId.get();
    return _repository.getSingleStoreOptions(listId, ownerRef);
  }

  /// Aplica todos los reemplazos de una opción: cada producto que no tiene ese
  /// supermercado se cambia por su sustituto, conservando la cantidad. Se hace de a uno
  /// (agrega el nuevo y sólo entonces quita el anterior), así que si algo falla a la
  /// mitad nunca se pierde un producto. Devuelve cuántos reemplazos se hicieron.
  Future<int> applySingleStoreOption(SingleStoreOption option) async {
    var hechos = 0;
    for (final r in option.applicable) {
      final item = detail?.items.where((i) => i.id == r.itemId).firstOrNull;
      if (item == null) continue;
      final ok = await replaceItem(item, r.substitute!.productId);
      if (!ok) break;
      hechos++;
    }
    return hechos;
  }

  /// Cambia un producto de la lista por otro, conservando la cantidad: agrega
  /// el nuevo y, sólo si se agregó, quita el anterior (nunca se pierde el
  /// producto si algo falla a la mitad).
  Future<bool> replaceItem(ShoppingListItem old, String newProductId) async {
    if (newProductId == old.productId) return true;
    final added = await addItem(newProductId, quantity: old.quantity);
    if (!added) return false;
    await removeItem(old.id);
    return true;
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
