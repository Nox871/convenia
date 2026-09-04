import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../models/product_list_item.dart';
import '../repositories/product_repository.dart';
import 'view_status.dart';

/// Filtro de la pantalla de Resultados. Se traduce 1:1 al parámetro
/// `supermarket` real del backend — nunca es un filtro inventado en cliente.
enum SupermarketFilter { all, d1, exito }

extension SupermarketFilterCode on SupermarketFilter {
  String? get apiCode {
    switch (this) {
      case SupermarketFilter.all:
        return null;
      case SupermarketFilter.d1:
        return 'D1';
      case SupermarketFilter.exito:
        return 'EXITO';
    }
  }

  String get label {
    switch (this) {
      case SupermarketFilter.all:
        return 'Todos';
      case SupermarketFilter.d1:
        return 'Mejor en D1';
      case SupermarketFilter.exito:
        return 'Mejor en Éxito';
    }
  }
}

/// Estado y lógica de la pantalla de Resultados: búsqueda, filtro y
/// paginación real contra `GET /api/products`. Los widgets solo leen este
/// controller y disparan sus métodos; no hacen HTTP directamente.
class SearchResultsController extends ChangeNotifier {
  final ProductRepository _repository;

  SearchResultsController({required String query, ProductRepository? repository})
    : _query = query,
      _repository = repository ?? ProductRepository() {
    _load();
  }

  static const _pageSize = 20;

  String _query;
  SupermarketFilter _filter = SupermarketFilter.all;
  ViewStatus status = ViewStatus.loading;
  String? errorMessage;

  final List<ProductListItem> _items = [];
  int _total = 0;
  int _page = 1;
  bool _hasNext = false;
  bool _isLoadingMore = false;

  String get query => _query;
  SupermarketFilter get filter => _filter;
  List<ProductListItem> get items => List.unmodifiable(_items);
  int get total => _total;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasNext => _hasNext;

  Future<void> updateQuery(String newQuery) async {
    if (newQuery.trim() == _query.trim()) return;
    _query = newQuery;
    await _load();
  }

  Future<void> setFilter(SupermarketFilter filter) async {
    if (filter == _filter) return;
    _filter = filter;
    await _load();
  }

  Future<void> retry() => _load();

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasNext) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final response = await _repository.searchProducts(
        query: _query,
        supermarket: _filter.apiCode,
        page: _page + 1,
        limit: _pageSize,
      );
      _items.addAll(response.items);
      _page = response.pagination.page;
      _hasNext = response.pagination.hasNext;
      _total = response.pagination.total;
    } on ApiException {
      // Fallo al paginar: se conserva lo ya cargado, no se rompe la lista.
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _load() async {
    status = ViewStatus.loading;
    notifyListeners();

    try {
      final response = await _repository.searchProducts(
        query: _query,
        supermarket: _filter.apiCode,
        page: 1,
        limit: _pageSize,
      );
      _items
        ..clear()
        ..addAll(response.items);
      _page = response.pagination.page;
      _hasNext = response.pagination.hasNext;
      _total = response.pagination.total;
      status = _items.isEmpty ? ViewStatus.empty : ViewStatus.loaded;
    } on ApiException catch (e) {
      status = ViewStatus.error;
      errorMessage = e.message;
    }

    notifyListeners();
  }
}
