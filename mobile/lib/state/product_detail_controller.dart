import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../models/compare_response.dart';
import '../models/product_detail.dart';
import '../repositories/product_repository.dart';
import 'view_status.dart';

/// Estado de la pantalla Detalle/Comparación.
///
/// Combina `GET /api/products/{id}` (metadata del producto) y
/// `GET /api/products/{id}/compare` (ofertas + mejor precio, ya calculado
/// por el backend con datos reales). No se usa `/prices` aquí porque
/// `/compare` ya incluye el mismo listado de ofertas más el mejor precio;
/// `ProductRepository.getProductPrices` queda disponible para un caso de uso
/// futuro que solo necesite precios sin la comparación.
class ProductDetailController extends ChangeNotifier {
  final String productId;
  final ProductRepository _repository;

  ProductDetailController({required this.productId, ProductRepository? repository})
    : _repository = repository ?? ProductRepository() {
    _load();
  }

  ViewStatus status = ViewStatus.loading;
  String? errorMessage;
  ProductDetail? detail;
  CompareResponse? comparison;

  Future<void> retry() => _load();

  Future<void> _load() async {
    status = ViewStatus.loading;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.getProductDetail(productId),
        _repository.compareProduct(productId),
      ]);
      detail = results[0] as ProductDetail;
      comparison = results[1] as CompareResponse;
      status = ViewStatus.loaded;
    } on NotFoundException catch (e) {
      status = ViewStatus.empty;
      errorMessage = e.message;
    } on ApiException catch (e) {
      status = ViewStatus.error;
      errorMessage = e.message;
    }

    notifyListeners();
  }
}
