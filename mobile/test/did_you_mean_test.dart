import 'package:convenia_mobile/models/page_info.dart';
import 'package:convenia_mobile/models/product_list_item.dart';
import 'package:convenia_mobile/models/product_list_response.dart';
import 'package:convenia_mobile/repositories/product_repository.dart';
import 'package:convenia_mobile/state/search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo extends ProductRepository {
  final int total;
  final String? correction;
  final List<String> asked = [];

  _FakeRepo({required this.total, this.correction});

  @override
  Future<ProductListResponse> searchProducts({
    String? query,
    String? category,
    String? supermarket,
    String sort = 'price',
    int page = 1,
    int limit = 20,
  }) async {
    final items = [
      for (var i = 0; i < total; i++)
        ProductListItem(
          id: 'sp-$i',
          name: 'Arroz $i',
          brand: null,
          imageUrl: null,
          supermarketCode: 'D1',
          supermarketName: 'D1',
          price: 1000,
          listPrice: null,
          currency: 'COP',
          offersCount: 1,
          isMatched: false,
        ),
    ];
    return ProductListResponse(
      items: items,
      pagination: PageInfo(
        page: 1, limit: limit, total: total, totalPages: 1, hasNext: false, hasPrev: false),
    );
  }

  @override
  Future<String?> didYouMean(String query) async {
    asked.add(query);
    return correction;
  }
}

void main() {
  test('sin resultados y con corrección, sugiere y al aceptarla busca de nuevo', () async {
    final repo = _FakeRepo(total: 0, correction: 'arroz');
    final c = SearchResultsController(query: 'aroz', repository: repo);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.suggestion, 'arroz');
    await c.acceptSuggestion();
    expect(c.query, 'arroz');
    expect(c.suggestion, isNull); // la búsqueda nueva limpia la sugerencia
  });

  test('con muchos resultados no pregunta por ortografía', () async {
    final repo = _FakeRepo(total: 10, correction: 'arroz');
    final c = SearchResultsController(query: 'arroz', repository: repo);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.suggestion, isNull);
    expect(repo.asked, isEmpty);
  });

  test('si el servidor no tiene corrección, no muestra nada', () async {
    final repo = _FakeRepo(total: 0, correction: null);
    final c = SearchResultsController(query: 'xyzxyz', repository: repo);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.suggestion, isNull);
  });
}
