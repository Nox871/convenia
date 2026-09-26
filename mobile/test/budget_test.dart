import 'package:convenia_mobile/core/budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareToBudget', () {
    test('sobra dinero cuando el total es menor al presupuesto', () {
      final c = compareToBudget(70000, 58400)!;

      expect(c.isWithin, isTrue);
      expect(c.difference, 11600);
      expect(c.usedFraction, closeTo(0.834, 0.001));
    });

    test('se pasa cuando el total supera el presupuesto', () {
      final c = compareToBudget(70000, 72300)!;

      expect(c.isWithin, isFalse);
      expect(c.difference, -2300);
      expect(c.usedFraction, greaterThan(1.0));
    });

    test('justo en el tope cuenta como dentro del presupuesto', () {
      expect(compareToBudget(70000, 70000)!.isWithin, isTrue);
    });

    test('sin presupuesto o sin total no hay comparación inventada', () {
      expect(compareToBudget(null, 50000), isNull);
      expect(compareToBudget(70000, null), isNull);
      expect(compareToBudget(null, null), isNull);
    });

    test('un presupuesto de cero con algún gasto se considera excedido', () {
      final c = compareToBudget(0, 1000)!;

      expect(c.isWithin, isFalse);
      expect(c.usedFraction, greaterThan(1.0));
    });
  });
}
