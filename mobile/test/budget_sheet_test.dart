import 'package:convenia_mobile/models/basket.dart';
import 'package:convenia_mobile/widgets/budget_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BudgetChoice?> _open(WidgetTester tester, void Function(BudgetChoice?) onResult) async {
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => onResult(
              await showBudgetSheet(context, listName: 'Desayuno básico', productCount: 8),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return null;
}

void main() {
  testWidgets('sin monto ni "sin límite" no se puede armar', (tester) async {
    await _open(tester, (_) {});
    final armar = find.widgetWithText(ElevatedButton, 'Armar lista');
    expect(tester.widget<ElevatedButton>(armar).onPressed, isNull);
  });

  testWidgets('un monto sugerido y un nivel se devuelven tal cual', (tester) async {
    BudgetChoice? result;
    await _open(tester, (r) => result = r);

    await tester.tap(find.text(r'$30.000'));
    await tester.pump();
    await tester.tap(find.text('Económica'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Armar lista'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.budget, 30000);
    expect(result!.tier, SpendTier.economico);
  });

  testWidgets('un monto escrito a mano se entiende', (tester) async {
    BudgetChoice? result;
    await _open(tester, (r) => result = r);

    await tester.enterText(find.byType(TextField), '45000');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Armar lista'));
    await tester.pumpAndSettle();

    expect(result!.budget, 45000);
    expect(result!.tier, SpendTier.medio); // nivel por defecto
  });

  testWidgets('"Sin límite" arma sin presupuesto', (tester) async {
    BudgetChoice? result;
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('Sin límite'));
    await tester.pump();
    await tester.tap(find.text('Completa'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Armar lista'));
    await tester.pumpAndSettle();

    expect(result!.budget, isNull);
    expect(result!.tier, SpendTier.alto);
  });

  testWidgets('Cancelar devuelve null', (tester) async {
    BudgetChoice? result = (tier: SpendTier.medio, budget: 1);
    await _open(tester, (r) => result = r);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
