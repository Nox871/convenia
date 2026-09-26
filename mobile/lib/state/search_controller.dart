import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../models/product_list_item.dart';
import '../repositories/product_repository.dart';
import 'view_status.dart';

/// Criterio de orden de Resultados (estilo Google Flights: pocos criterios
/// claros, nunca una lista fija de supermercados). `distance` existe en el
/// enum pero el backend no lo soporta todavía (no hay `physical_stores`
/// reales) -- se deja definido para activarlo sin romper el contrato de la
/// UI el día que haya datos, pero la UI nunca debe ofrecerlo mientras tanto.
enum ResultsSort { price, recent }

extension ResultsSortCode on ResultsSort {
  String get apiValue => switch (this) { ResultsSort.price => 'price', ResultsSort.recent => 'recent' };

  String get label => switch (this) {
    ResultsSort.price => 'Menor precio',
    ResultsSort.recent => 'Más reciente',
  };
}

/// Estado y lógica de la pantalla de Resultados: búsqueda, orden y
/// paginación real contra `GET /api/v1/products`. Los widgets solo leen este
/// controller y disparan sus métodos; no hacen HTTP directamente.
class SearchResultsController extends ChangeNotifier {
  final ProductRepository _repository;

  SearchResultsController({String query = '', String? category, ProductRepository? repository})
    : _query = query,
      _category = category,
      _repository = repository ?? ProductRepository() {
    _load();
  }

  static const _pageSize = 20;

  String _query;
  String? _category;
  ResultsSort _sort = ResultsSort.price;
  String? _supermarketFilter; // filtro avanzado oculto, null = todos
  ViewStatus status = ViewStatus.loading;
  String? errorMessage;

  final List<ProductListItem> _items = [];
  int _total = 0;
  int _page = 1;
  bool _hasNext = false;
  bool _isLoadingMore = false;

  String get query => _query;
  String? get category => _category;
  ResultsSort get sort => _sort;
  String? get supermarketFilter => _supermarketFilter;
  List<ProductListItem> get items => List.unmodifiable(_items);
  int get total => _total;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasNext => _hasNext;

  /// Cambiar la búsqueda de texto siempre reemplaza el filtro de categoría
  /// (son dos formas alternativas de llegar a Resultados, no combinables
  /// desde este cuadro de edición).
  Future<void> updateQuery(String newQuery) async {
    if (newQuery.trim() == _query.trim() && _category == null) return;
    _query = newQuery;
    _category = null;
    await _load();
  }

  Future<void> setSort(ResultsSort sort) async {
    if (sort == _sort) return;
    _sort = sort;
    await _load();
  }

  Future<void> setSupermarketFilter(String? code) async {
    if (code == _supermarketFilter) return;
    _supermarketFilter = code;
    await _load();
  }

  Future<void> retry() => _load();

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasNext) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final response = await _repository.searchProducts(
        query: _category == null ? _query : null,
        category: _category,
        supermarket: _supermarketFilter,
        sort: _sort.apiValue,
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
        query: _category == null ? _query : null,
        category: _category,
        supermarket: _supermarketFilter,
        sort: _sort.apiValue,
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
