import 'package:convenia_mobile/models/shopping_list.dart';
import 'package:convenia_mobile/repositories/shopping_list_repository.dart';
import 'package:convenia_mobile/state/shopping_list_detail_controller.dart';
import 'package:convenia_mobile/state/shopping_lists_controller.dart';
import 'package:convenia_mobile/state/view_status.dart';
import 'package:convenia_mobile/widgets/app_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShoppingListItem _item(int id, String productId, String name, {int quantity = 1}) => ShoppingListItem(
      id: id,
      productId: productId,
      name: name,
      brand: null,
      imageUrl: null,
      quantity: quantity,
    );

ShoppingListDetail _detail(List<ShoppingListItem> items) => ShoppingListDetail(
      id: 1,
      name: 'Desayunos',
      createdAt: DateTime(2026, 10, 4),
      updatedAt: DateTime(2026, 10, 4),
      budget: null,
      items: items,
    );

ShoppingListSummary _summary(int count) => ShoppingListSummary(
      id: 1,
      name: 'Desayunos',
      createdAt: DateTime(2026, 10, 4),
      updatedAt: DateTime(2026, 10, 4),
      itemsCount: count,
    );

class _FakeRepo extends ShoppingListRepository {
  List<ShoppingListItem> items = [_item(10, 'p-1', 'Huevo sorpresa OZMO', quantity: 3)];
  int summaryCount = 0;
  bool failAdd = false;
  final calls = <String>[];

  @override
  Future<List<ShoppingListSummary>> listLists(String ownerRef) async => [_summary(summaryCount)];

  @override
  Future<ShoppingListDetail> getList(int listId, String ownerRef) async => _detail(items);

  @override
  Future<ShoppingListCostResponse> getCost(int listId, String ownerRef) async =>
      ShoppingListCostResponse(listId: listId, costs: const [], bestSupermarketCode: null);

  @override
  Future<ShoppingListDistributedResponse> getDistributedPlan(int listId, String ownerRef) async =>
      ShoppingListDistributedResponse(
        listId: listId,
        totalCost: 9000,
        stops: [
          DistributedPlanStop(
            supermarketCode: 'JUMBO',
            supermarketName: 'Jumbo',
            subtotal: 9000,
            items: [DistributedPlanItem(itemId: 10, name: 'Huevo sorpresa OZMO', quantity: 3, unitPrice: 3000, subtotal: 9000)],
          ),
        ],
        unpricedItemIds: const [11],
      );

  @override
  Future<ShoppingListDetail> addItem(int listId, String ownerRef, String productId, {int quantity = 1}) async {
    calls.add('add $productId x$quantity');
    if (failAdd) throw Exception('sin red');
    items = [...items, _item(99, productId, 'Huevos AA 12 und', quantity: quantity)];
    return _detail(items);
  }

  @override
  Future<ShoppingListDetail> deleteItem(int listId, int itemId, String ownerRef) async {
    calls.add('delete $itemId');
    items = items.where((i) => i.id != itemId).toList();
    return _detail(items);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Mis listas', () {
    test('refresh actualiza el conteo SIN pasar por la rueda de carga', () async {
      final repo = _FakeRepo();
      final c = ShoppingListsController(repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.lists.first.itemsCount, 0);

      final estados = <ViewStatus>[];
      c.addListener(() => estados.add(c.status));
      repo.summaryCount = 5; // se agregaron productos en otra pantalla
      await c.refresh();

      expect(c.lists.first.itemsCount, 5);
      expect(estados.every((s) => s == ViewStatus.loaded), isTrue); // nunca volvió a "loading"
    });

    test('la señal externa (abrir la pestaña) dispara la recarga', () async {
      final repo = _FakeRepo();
      final signal = ValueNotifier<int>(0);
      final c = ShoppingListsController(repository: repo, refreshSignal: signal);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repo.summaryCount = 7;
      signal.value++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.lists.first.itemsCount, 7);
      c.dispose();
      signal.value++; // ya sin oyentes: no debe fallar
    });
  });

  group('Detalle de la lista', () {
    test('cada producto sabe en qué supermercado conviene comprarlo', () async {
      final c = ShoppingListDetailController(listId: 1, repository: _FakeRepo());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final a = c.assignments[10]!;
      expect(a.store, 'Jumbo');
      expect(a.subtotal, 9000);
      expect(c.unpricedItemIds, {11});
    });

    test('cambiar un producto agrega el nuevo con la misma cantidad y quita el anterior', () async {
      final repo = _FakeRepo();
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final ok = await c.replaceItem(c.detail!.items.first, 'p-2');
      expect(ok, isTrue);
      expect(repo.calls, ['add p-2 x3', 'delete 10']);
      expect(c.detail!.items.map((i) => i.productId), ['p-2']);
      expect(c.savedAt, isNotNull); // el cambio quedó guardado y visible
    });

    test('si no se puede agregar el nuevo, NO se quita el anterior', () async {
      final repo = _FakeRepo()..failAdd = true;
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // addItem lanza una Exception genérica: replaceItem debe propagarla sin borrar
      await expectLater(c.replaceItem(c.detail!.items.first, 'p-2'), throwsException);
      expect(repo.calls, ['add p-2 x3']); // nunca llegó a borrar
      expect(c.detail!.items.length, 1);
    });

    test('cambiar por el mismo producto no hace nada', () async {
      final repo = _FakeRepo();
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await c.replaceItem(c.detail!.items.first, 'p-1'), isTrue);
      expect(repo.calls, isEmpty);
    });
  });

  group('Cierre de la lista ("Listo")', () {
    test('si una tienda tiene todo, el cierre dice dónde comprar y cuánto', () async {
      final repo = _CostRepo(best: true);
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.finishSummary(), '«Desayunos» guardada · comprándola en Jumbo: \$61.225');
    });

    test('si ninguna la tiene completa, el cierre cuenta la compra repartida', () async {
      final repo = _CostRepo(best: false);
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.finishSummary(), '«Desayunos» guardada · repartida en 2 supermercados: \$36.782');
    });

    test('una lista vacía sólo confirma que se guardó', () async {
      final repo = _CostRepo(best: true)..items = [];
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.finishSummary(), '«Desayunos» guardada');
    });
  });

  group('Hojas', () {
    Future<void> abrir(WidgetTester tester, Future<void> Function(BuildContext) accion) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: ElevatedButton(onPressed: () => accion(context), child: const Text('abrir'))),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('confirmar: Cancelar y Eliminar van lado a lado y devuelven false/true', (tester) async {
      bool? resultado;
      await abrir(tester, (c) async => resultado = await showConfirmSheet(c, title: 'Eliminar', message: 'x'));
      final cancelar = tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Cancelar'));
      final eliminar = tester.getTopLeft(find.widgetWithText(ElevatedButton, 'Eliminar'));
      expect(cancelar.dx, lessThan(eliminar.dx));
      expect((cancelar.dy - eliminar.dy).abs(), lessThan(1));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(resultado, isTrue);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(resultado, isFalse);
    });

    testWidgets('renombrar: Guardar se activa con texto y devuelve el nombre', (tester) async {
      String? nombre;
      await abrir(tester, (c) async => nombre = await showTextSheet(c, title: 'Renombrar', initial: 'Desayunos'));
      await tester.enterText(find.byType(TextField), 'Desayunos de la semana');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(nombre, 'Desayunos de la semana');
    });

    testWidgets('presupuesto: quitar el presupuesto existente', (tester) async {
      AmountResult? r;
      await abrir(tester, (c) async => r = await showAmountSheet(c, title: 'Presupuesto', initial: 30000, allowRemove: true));
      await tester.tap(find.text('Quitar el presupuesto'));
      await tester.pumpAndSettle();
      expect(r!.remove, isTrue);
    });

    testWidgets('presupuesto: un monto nuevo se devuelve como número', (tester) async {
      AmountResult? r;
      await abrir(tester, (c) async => r = await showAmountSheet(c, title: 'Presupuesto'));
      await tester.enterText(find.byType(TextField), '45000');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(r!.value, 45000);
      expect(r!.remove, isFalse);
    });
  });
}


/// Repositorio falso con costos por supermercado (para probar el cierre).
class _CostRepo extends _FakeRepo {
  final bool best;

  _CostRepo({required this.best});

  @override
  Future<ShoppingListCostResponse> getCost(int listId, String ownerRef) async => ShoppingListCostResponse(
        listId: listId,
        bestSupermarketCode: best ? 'JUMBO' : null,
        costs: [
          SupermarketCost(
            supermarketCode: 'JUMBO',
            supermarketName: 'Jumbo',
            totalCost: 61225,
            itemsPriced: best ? 1 : 0,
            itemsTotal: 1,
            isComplete: best,
          ),
        ],
      );

  @override
  Future<ShoppingListDistributedResponse> getDistributedPlan(int listId, String ownerRef) async =>
      ShoppingListDistributedResponse(
        listId: listId,
        totalCost: 36782,
        unpricedItemIds: const [],
        stops: [
          DistributedPlanStop(supermarketCode: 'JUMBO', supermarketName: 'Jumbo', subtotal: 14312, items: const []),
          DistributedPlanStop(supermarketCode: 'EXITO', supermarketName: 'Éxito', subtotal: 22470, items: const []),
        ],
      );
}
