import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
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

  Future<void> retry() => _load();

  Future<void> _load() async {
    status = ViewStatus.loading;
    notifyListeners();

    try {
      final result = await _repository.getPriceHistoryMonthly(productId);
      months = result.months;
      status = months.isEmpty ? ViewStatus.empty : ViewStatus.loaded;
    } on ApiException catch (e) {
      status = ViewStatus.error;
      errorMessage = e.message;
    }

    notifyListeners();
  }
}
