import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../models/supermarket.dart';
import '../repositories/supermarket_repository.dart';
import 'view_status.dart';

/// Estado de la pantalla "Configuración" (ERS §23.8): fuente de datos y
/// fecha de la última actualización exitosa de cada supermercado (sección
/// 42: nunca se afirma que un precio es "actual" sin decir cuándo se
/// observó por última vez).
class SettingsController extends ChangeNotifier {
  final SupermarketRepository _repository;

  SettingsController({SupermarketRepository? repository})
    : _repository = repository ?? SupermarketRepository() {
    _load();
  }

  ViewStatus status = ViewStatus.loading;
  String? errorMessage;
  List<Supermarket> supermarkets = [];

  Future<void> retry() => _load();

  Future<void> _load() async {
    status = ViewStatus.loading;
    notifyListeners();

    try {
      final result = await _repository.listSupermarkets();
      supermarkets = result;
      status = ViewStatus.loaded;
    } on ApiException catch (e) {
      status = ViewStatus.error;
      errorMessage = e.message;
    }

    notifyListeners();
  }
}
