import 'package:convenia_mobile/core/price_trend.dart';
import 'package:convenia_mobile/models/price_history_response.dart';
import 'package:flutter_test/flutter_test.dart';

PriceHistoryPoint _obs(DateTime t, double price, {bool available = true}) => PriceHistoryPoint(
      price: price,
      listPrice: null,
      currency: 'COP',
      available: available,
      observedAt: t,
    );

List<DailyPrice> _serie(List<double> precios) => [
      for (var i = 0; i < precios.length; i++) DailyPrice(DateTime(2026, 10, 1 + i), precios[i]),
    ];

void main() {
  group('toDailySeries', () {
    test('una fecha repetida se colapsa al menor precio del día', () {
      final out = toDailySeries([
        _obs(DateTime(2026, 10, 3, 8), 3300),
        _obs(DateTime(2026, 10, 3, 9), 2793),
        _obs(DateTime(2026, 10, 3, 10), 2904),
        _obs(DateTime(2026, 10, 2, 8), 2656),
      ]);
      expect(out.length, 2);
      expect(out.first.day, DateTime(2026, 10, 2));
      expect(out.last.price, 2793);
    });

    test('ignora precios en 0 y observaciones no disponibles', () {
      final out = toDailySeries([
        _obs(DateTime(2026, 10, 3), 0),
        _obs(DateTime(2026, 10, 4), 1500, available: false),
        _obs(DateTime(2026, 10, 5), 1800),
      ]);
      expect(out.map((p) => p.price), [1800]);
    });

    test('queda ordenada de la más antigua a la más reciente', () {
      final out = toDailySeries([
        _obs(DateTime(2026, 10, 5), 1),
        _obs(DateTime(2026, 10, 1), 2),
        _obs(DateTime(2026, 10, 3), 3),
      ]);
      expect(out.map((p) => p.day.day), [1, 3, 5]);
    });
  });

  group('estimateTrend', () {
    test('con menos de 7 días no estima nada (no inventa un patrón)', () {
      expect(estimateTrend(_serie([1000, 1010, 1020])), isNull);
      expect(estimateTrend(_serie([1000, 1010, 1020, 1030, 1040, 1050])), isNull);
    });

    test('precio que sube de forma constante: tendencia al alza y proyección creciente', () {
      final t = estimateTrend(_serie([1000, 1050, 1100, 1150, 1200, 1250, 1300]))!;
      expect(t.direction, TrendDirection.up);
      expect(t.weeklyPercent, greaterThan(1));
      expect(t.projection.length, 7);
      expect(t.projection.first.price, closeTo(1350, 1));
      expect(t.projection.last.price, closeTo(1650, 1));
      expect(t.projection.first.day, DateTime(2026, 10, 8));
    });

    test('precio que baja: tendencia a la baja', () {
      final t = estimateTrend(_serie([2000, 1950, 1900, 1850, 1800, 1750, 1700]))!;
      expect(t.direction, TrendDirection.down);
      expect(t.weeklyPercent, lessThan(-1));
    });

    test('precio constante: estable y proyección plana', () {
      final t = estimateTrend(_serie([1500, 1500, 1500, 1500, 1500, 1500, 1500]))!;
      expect(t.direction, TrendDirection.stable);
      expect(t.projection.every((p) => p.price == 1500), isTrue);
    });

    test('precios que saltan sin patrón: sin tendencia clara y sin proyección', () {
      final t = estimateTrend(_serie([1000, 1800, 1100, 1900, 1050, 1850, 1000, 1900]))!;
      expect(t.direction, TrendDirection.unclear);
      expect(t.projection, isEmpty);
    });

    test('nunca proyecta precios negativos', () {
      final t = estimateTrend(_serie([700, 600, 500, 400, 300, 200, 100]))!;
      expect(t.projection.every((p) => p.price >= 0), isTrue);
    });
  });
}
