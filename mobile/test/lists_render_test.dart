import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:convenia_mobile/models/shopping_list.dart';
import 'package:convenia_mobile/repositories/shopping_list_repository.dart';
import 'package:convenia_mobile/screens/shopping_list_detail_screen.dart';
import 'package:convenia_mobile/screens/shopping_lists_screen.dart';
import 'package:convenia_mobile/state/coverage_controller.dart';
import 'package:convenia_mobile/state/shopping_list_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShoppingListItem _item(int id, String name, {String? brand, int q = 1}) =>
    ShoppingListItem(
        id: id,
        productId: 'p-$id',
        name: name,
        brand: brand,
        imageUrl: null,
        quantity: q);

class _Repo extends ShoppingListRepository {
  final items = [
    _item(1, 'Pan Perro BIMBO x6und (205 gr)', brand: 'Bimbo'),
    _item(2, 'Huevo sorpresa OZMO 20 GRS', brand: 'OZMO', q: 2),
    _item(3, 'Pera 1 und', brand: 'Sm'),
  ];

  @override
  Future<ShoppingListDetail> getList(int listId, String ownerRef) async =>
      ShoppingListDetail(
          id: 1,
          name: 'Desayunos',
          createdAt: DateTime(2026, 10, 4),
          updatedAt: DateTime(2026, 10, 4),
          budget: null,
          items: items);

  @override
  Future<ShoppingListCostResponse> getCost(int listId, String ownerRef) async =>
      ShoppingListCostResponse(
        listId: listId,
        bestSupermarketCode: null,
        costs: const [
          SupermarketCost(
              supermarketCode: 'EXITO',
              supermarketName: 'Éxito',
              totalCost: 35230,
              itemsPriced: 2,
              itemsTotal: 3,
              isComplete: false,
              missingItemIds: [3]),
          SupermarketCost(
              supermarketCode: 'JUMBO',
              supermarketName: 'Jumbo',
              totalCost: 35292,
              itemsPriced: 2,
              itemsTotal: 3,
              isComplete: false,
              missingItemIds: [2]),
          SupermarketCost(
              supermarketCode: 'D1',
              supermarketName: 'D1',
              totalCost: null,
              itemsPriced: 0,
              itemsTotal: 3,
              isComplete: false,
              missingItemIds: [1, 2, 3]),
        ],
      );

  @override
  Future<ShoppingListDistributedResponse> getDistributedPlan(
          int listId, String ownerRef) async =>
      ShoppingListDistributedResponse(
        listId: listId,
        totalCost: 36782,
        unpricedItemIds: const [],
        stops: [
          DistributedPlanStop(
              supermarketCode: 'JUMBO',
              supermarketName: 'Jumbo',
              subtotal: 14312,
              items: [
                DistributedPlanItem(
                    itemId: 1,
                    name: 'Pan Perro BIMBO',
                    quantity: 1,
                    unitPrice: 4280,
                    subtotal: 4280),
              ]),
          DistributedPlanStop(
              supermarketCode: 'EXITO',
              supermarketName: 'Éxito',
              subtotal: 22470,
              items: [
                DistributedPlanItem(
                    itemId: 2,
                    name: 'Huevo sorpresa',
                    quantity: 2,
                    unitPrice: 5000,
                    subtotal: 10000),
                DistributedPlanItem(
                    itemId: 3,
                    name: 'Pera',
                    quantity: 1,
                    unitPrice: 1200,
                    subtotal: 1200),
              ]),
        ],
      );
}

Future<void> _render(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['CHART_OUT'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// google_fonts intenta bajar Manrope por red y en pruebas falla de forma asíncrona:
  /// esa descarga se ignora; cualquier otro error (un desborde, un expect) sí falla.
  Future<void> sinDescargaDeFuentes(Future<void> Function() cuerpo) {
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

  testWidgets(
      'detalle de la lista: tienda asignada por producto, Cambiar, y barra Guardado/Listo',
      (tester) async {
    tester.view.physicalSize = const Size(720, 5600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await sinDescargaDeFuentes(() async {
      final key = GlobalKey();
      final controller =
          ShoppingListDetailController(listId: 1, repository: _Repo());
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: ChangeNotifierProvider(
          // el alcance de supermercados vive en la raíz de la app
          create: (_) => CoverageController(),
          child: MaterialApp(
              home: ShoppingListDetailScreen(listId: 1, controller: controller)),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // cada producto muestra dónde comprarlo
      expect(find.textContaining('Jumbo · '), findsWidgets);
      expect(find.textContaining('Éxito · '), findsWidgets);
      // cambiar y cerrar
      expect(find.text('Cambiar'), findsNWidgets(3));
      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Agregar'), findsOneWidget);
      expect(find.textContaining('Se guarda automáticamente'), findsOneWidget);
      // lo de abajo viene plegado: sólo el resumen de cada sección
      expect(find.text('Comparar supermercados'), findsOneWidget);
      expect(find.text('Qué comprar en cada supermercado'), findsOneWidget);
      expect(find.text('Cómo ahorrar'), findsNothing); // sin presupuesto no hay nada que ahorrar
      expect(find.textContaining('Tiene 2 de 3 productos'), findsNothing); // plegado

      // al abrir "Comparar supermercados": sólo los que tienen algo de la lista
      await tester.ensureVisible(find.text('Comparar supermercados'));
      await tester.tap(find.text('Comparar supermercados'));
      await tester.pump();
      expect(find.textContaining('Tiene 2 de 3 productos'), findsNWidgets(2));
      expect(find.text('Sin datos'), findsNothing);
      expect(find.text('D1'), findsNothing); // D1 no tiene ninguno: ni aparece
      expect(find.textContaining('Le falta: Pera'), findsOneWidget);
      // a un solo producto de la meta se resalta (gradiente de meta)
      expect(find.textContaining('¡solo le falta 1!'), findsNWidgets(2));
      await _render(tester, key, 'detalle_lista');
    });
  });

  testWidgets('tarjetas de Mis listas: vacía, con productos y con presupuesto',
      (tester) async {
    tester.view.physicalSize = const Size(720, 900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    ShoppingListSummary s(String n, int c, {int? b, DateTime? t}) =>
        ShoppingListSummary(
            id: 1,
            name: n,
            createdAt: DateTime.now(),
            updatedAt: t ?? DateTime.now(),
            itemsCount: c,
            budget: b);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F5EF),
        body: RepaintBoundary(
          key: key,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ShoppingListCard(list: s('Desayunos', 0), onTap: () {}),
                const SizedBox(height: 8),
                ShoppingListCard(
                    list: s('Mercado semanal', 8,
                        b: 150000,
                        t: DateTime.now().subtract(const Duration(hours: 3))),
                    onTap: () {}),
                const SizedBox(height: 8),
                ShoppingListCard(
                    list: s('Aseo del hogar', 1,
                        t: DateTime.now().subtract(const Duration(days: 2))),
                    onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Vacía · toca para agregar productos'), findsOneWidget);
    expect(find.textContaining('8 productos · hace 3 h'), findsOneWidget);
    expect(find.textContaining('1 producto · hace 2 días'), findsOneWidget);
    expect(find.textContaining('Presupuesto'), findsOneWidget);
    await _render(tester, key, 'mis_listas');
  });
}
