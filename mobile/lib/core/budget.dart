import '../models/shopping_list.dart';

/// Comparación entre el presupuesto de una lista y lo que cuesta comprarla.
class BudgetComparison {
  final int budget;
  final double total;

  const BudgetComparison({required this.budget, required this.total});

  /// Positivo = sobra dinero; negativo = el total se pasa del presupuesto.
  double get difference => budget - total;

  bool get isWithin => difference >= 0;

  /// Fracción del presupuesto que se gasta (puede pasar de 1.0 si se excede).
  double get usedFraction => budget == 0 ? (total > 0 ? 2.0 : 0.0) : total / budget;
}

/// Compara `budget` contra `total`. Devuelve `null` si falta alguno de los
/// dos -- sin presupuesto o sin un total confiable no hay nada que comparar,
/// y nunca se inventa uno.
BudgetComparison? compareToBudget(int? budget, double? total) {
  if (budget == null || total == null) return null;
  return BudgetComparison(budget: budget, total: total);
}

/// El total contra el cual se compara el presupuesto: el del mejor
/// supermercado que tiene la lista COMPLETA. Si ninguno la tiene completa,
/// no hay un total comparable y se devuelve `null` (comparar un total
/// parcial contra el presupuesto diría "te sobra" cuando en realidad faltan
/// productos por cotizar).
double? completeListTotal(ShoppingListCostResponse cost) {
  final bestCode = cost.bestSupermarketCode;
  if (bestCode == null) return null;
  for (final c in cost.costs) {
    if (c.supermarketCode == bestCode) return c.totalCost;
  }
  return null;
}

/// El total del plan repartido, sólo si TODOS los productos quedaron con
/// precio; con productos sin precio el total sería parcial.
double? distributedTotal(ShoppingListDistributedResponse? plan) {
  if (plan == null || plan.totalCost == null) return null;
  return plan.unpricedItemIds.isEmpty ? plan.totalCost : null;
}
