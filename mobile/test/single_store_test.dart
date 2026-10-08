import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:convenia_mobile/models/shopping_list.dart';
import 'package:convenia_mobile/models/single_store.dart';
import 'package:convenia_mobile/models/swap_suggestion.dart';
import 'package:convenia_mobile/repositories/shopping_list_repository.dart';
import 'package:convenia_mobile/state/shopping_list_detail_controller.dart';
import 'package:convenia_mobile/widgets/single_store_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShoppingListItem _item(int id, String name, {int q = 1}) =>
    ShoppingListItem(id: id, productId: 'p-$id', name: name, brand: null, imageUrl: null, quantity: q);

SwapAlternative _alt(String id, String name, double price) => SwapAlternative(
      productId: id,
      name: name,
      brand: null,
      imageUrl: null,
      unitPrice: price,
      supermarketCode: 'JUMBO',
      supermarketName: 'Jumbo',
    );

SingleStoreOption _jumbo({bool completable = true}) => SingleStoreOption(
      supermarketCode: 'JUMBO',
      supermarketName: 'Jumbo',
      itemsTotal: 3,
      itemsPriced: 1,
      currentTotal: 9000,
      completable: completable,
      totalIfReplaced: completable ? 27200 : null,
      replacements: [
        SingleStoreReplacement(itemId: 2, itemName: 'Pollo Azteca Desmechado 300g', quantity: 2, substitute: _alt('sp-50', 'Pollo desmechado Pimpollo 300g', 6000)),
        SingleStoreReplacement(
          itemId: 3,
          itemName: 'Cebolla polvo Mccormick x74g',
          quantity: 1,
          substitute: completable ? _alt('sp-51', 'Cebolla en polvo Badia 70 gr', 4200) : null,
        ),
      ],
    );

final SingleStoreOption _exito = SingleStoreOption(
  supermarketCode: 'EXITO',
  supermarketName: 'Éxito',
  itemsTotal: 3,
  itemsPriced: 1,
  currentTotal: 8500,
  completable: false,
  totalIfReplaced: null,
  replacements: const [
    SingleStoreReplacement(itemId: 2, itemName: 'Pollo Azteca Desmechado 300g', quantity: 2, substitute: null),
  ],
);

class _Repo extends ShoppingListRepository {
  List<ShoppingListItem> items = [_item(1, 'Arroz Doña Pepa 1000 gr'), _item(2, 'Pollo Azteca Desmechado 300g', q: 2), _item(3, 'Cebolla polvo Mccormick x74g')];
  List<SingleStoreOption> options = [];
  final calls = <String>[];
  bool failAdd = false;
  int nextId = 90;

  ShoppingListDetail _detail() => ShoppingListDetail(
        id: 1, name: 'Mercado del mes', createdAt: DateTime(2026), updatedAt: DateTime(2026), budget: null, items: items);

  @override
  Future<ShoppingListDetail> getList(int listId, String ownerRef) async => _detail();

  @override
  Future<ShoppingListCostResponse> getCost(int listId, String ownerRef) async =>
      ShoppingListCostResponse(listId: listId, costs: const [], bestSupermarketCode: null);

  @override
  Future<ShoppingListDistributedResponse> getDistributedPlan(int listId, String ownerRef) async =>
      ShoppingListDistributedResponse(listId: listId, totalCost: null, stops: const [], unpricedItemIds: const []);

  @override
  Future<List<SingleStoreOption>> getSingleStoreOptions(int listId, String ownerRef) async => options;

  @override
  Future<ShoppingListDetail> addItem(int listId, String ownerRef, String productId, {int quantity = 1}) async {
    calls.add('add $productId x$quantity');
    if (failAdd) throw Exception('sin red');
    items = [...items, _item(nextId++, 'nuevo $productId', q: quantity)];
    return _detail();
  }

  @override
  Future<ShoppingListDetail> deleteItem(int listId, int itemId, String ownerRef) async {
    calls.add('delete $itemId');
    items = items.where((i) => i.id != itemId).toList();
    return _detail();
  }
}

Future<void> _sinDescargaDeFuentes(Future<void> Function() cuerpo) {
  final done = Completer<void>();
  runZonedGuarded(() async {
    await cuerpo();
    if (!done.isCompleted) done.complete();
  }, (e, st) {
    if ('$e'.contains('Failed to load font')) return;
    if (!done.isCompleted) done.completeError(e, st);
  });
  return done.future;
}

final GlobalKey _raiz = GlobalKey();

Future<void> _render(WidgetTester tester, String nombre) async {
  final dir = Platform.environment['CHART_OUT'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = _raiz.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$nombre.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Aplicar una opción de un solo supermercado', () {
    test('cambia cada producto faltante por su sustituto, con la misma cantidad', () async {
      final repo = _Repo();
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final hechos = await c.applySingleStoreOption(_jumbo());

      expect(hechos, 2);
      // primero agrega el nuevo y sólo entonces quita el anterior, de a uno
      expect(repo.calls, ['add sp-50 x2', 'delete 2', 'add sp-51 x1', 'delete 3']);
      // queda el arroz original (1) y los dos nuevos (90, 91); el pollo (2) y la cebolla (3) se fueron
      expect(c.detail!.items.map((i) => i.id), [1, 90, 91]);
      expect(c.detail!.items.where((i) => i.id == 90).single.quantity, 2); // conserva la cantidad
    });

    test('si falla agregar un sustituto, se detiene y NO quita el producto original', () async {
      final repo = _Repo()..failAdd = true;
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await expectLater(c.applySingleStoreOption(_jumbo()), throwsException);
      expect(repo.calls, ['add sp-50 x2']); // nunca llegó a borrar
      expect(c.detail!.items.length, 3);
    });

    test('un reemplazo sin sustituto no se aplica', () async {
      final repo = _Repo();
      final c = ShoppingListDetailController(listId: 1, repository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await c.applySingleStoreOption(_exito), 0);
      expect(repo.calls, isEmpty);
      expect(_exito.applicable, isEmpty);
    });

    test('la opción cuenta cuántos productos quedan resueltos', () {
      final o = _jumbo();
      expect(o.applicable.length, 2);
      expect(o.coveredWithReplacements, 3); // 1 que ya tiene + 2 reemplazables
    });
  });

  group('Hoja "Comprar todo en un solo lugar"', () {
    Future<void> abrir(WidgetTester tester, ShoppingListDetailController c, void Function(SingleStoreDone?) alCerrar) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(key: _raiz, child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => alCerrar(await showSingleStoreSheet(context, c)),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('destaca UNA opción recomendada, muestra el progreso y deja ver los reemplazos', (tester) async {
      await _sinDescargaDeFuentes(() async {
        final repo = _Repo()..options = [_jumbo(), _exito];
        final c = ShoppingListDetailController(listId: 1, repository: repo);
        SingleStoreDone? cierre;
        await abrir(tester, c, (d) => cierre = d);
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Comprar todo en un solo lugar'), findsOneWidget);
        expect(find.text('Recomendado'), findsOneWidget); // sólo una destacada
        expect(find.text(r'$27.200'), findsOneWidget);
        expect(find.textContaining('1 de 3 ya los tiene'), findsOneWidget);
        expect(find.textContaining('2 se reemplazan por uno parecido'), findsOneWidget);
        // la otra opción es una fila compacta, no una tarjeta destacada
        expect(find.textContaining('Tiene 1 de 3 · no se completa'), findsOneWidget);
        await _render(tester, 'hoja_un_solo_lugar');

        await tester.tap(find.text('Ver los 2 reemplazos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600)); // termina el fundido entre vistas
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Completar en Jumbo'), findsOneWidget);
        expect(find.textContaining('Pollo desmechado Pimpollo 300g'), findsOneWidget);
        expect(find.textContaining('En vez de: Cebolla polvo Mccormick x74g'), findsOneWidget);
        await _render(tester, 'hoja_reemplazos');

        await tester.tap(find.text('Aplicar 2 cambios'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));

        expect(repo.calls, ['add sp-50 x2', 'delete 2', 'add sp-51 x1', 'delete 3']);
        expect(cierre, isNotNull);
        expect(cierre!.store, 'Jumbo');
        expect(cierre!.replaced, 2);
        expect(cierre!.total, 27200);
      });
    });

    testWidgets('si ninguna se puede completar lo dice claro y no recomienda nada', (tester) async {
      await _sinDescargaDeFuentes(() async {
        final repo = _Repo()..options = [_jumbo(completable: false), _exito];
        final c = ShoppingListDetailController(listId: 1, repository: repo);
        await abrir(tester, c, (_) {});
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Recomendado'), findsNothing);
        expect(find.textContaining('Ningún supermercado se puede completar'), findsOneWidget);
      });
    });

    testWidgets('sin ninguna opción explica que no hay productos de la lista a su alcance', (tester) async {
      await _sinDescargaDeFuentes(() async {
        final repo = _Repo()..options = [];
        final c = ShoppingListDetailController(listId: 1, repository: repo);
        await abrir(tester, c, (_) {});
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.textContaining('Ningún supermercado a tu alcance tiene productos de tu lista'), findsOneWidget);
      });
    });
  });
}
