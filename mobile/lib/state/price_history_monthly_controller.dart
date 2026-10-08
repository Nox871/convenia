import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../core/price_trend.dart';
import '../models/price_history_monthly_response.dart';
import '../repositories/product_repository.dart';
import 'view_status.dart';

/// Estado del historial visual (resumen mensual de barras). El drill-down de
/// un mes específico se resuelve aparte, en la propia hoja de detalle
/// (`_MonthDetailSheet`), reusando `getPriceHistory(productId, month: ...)`.
class PriceHistoryMonthlyController extends ChangeNotifier {
  final String productId;
  final ProductRepository _repository;

  PriceHistoryMonthlyController({required this.productId, ProductRepository? repository})
    : _repository = repository ?? ProductRepository() {
    _load();
  }

  ViewStatus status = ViewStatus.loading;
  String? errorMessage;
  List<PriceHistoryMonthlyPoint> months = [];

  /// Un precio por día, de la más antigua a la más reciente. Si no se pudo
  /// cargar, queda vacía y la pantalla muestra sólo las barras mensuales.
  List<DailyPrice> daily = [];

  Future<void> retry() => _load();

  Future<void> _load() async {
    status = ViewStatus.loading;
    notifyListeners();

    try {
      final dailyFuture = _repository
          .getPriceHistory(productId, limit: 100)
          .then<List<DailyPrice>>((r) => toDailySeries(r.observations))
          .catchError((_) => <DailyPrice>[]);
      final result = await _repository.getPriceHistoryMonthly(productId);
      months = result.months;
      daily = await dailyFuture;
      status = months.isEmpty ? ViewStatus.empty : ViewStatus.loaded;
    } on ApiException catch (e) {
      status = ViewStatus.error;
      errorMessage = e.message;
    }

    notifyListeners();
  }
}
