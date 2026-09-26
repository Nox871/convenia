import 'package:convenia_mobile/models/coverage.dart';
import 'package:convenia_mobile/state/coverage_controller.dart';
import 'package:convenia_mobile/state/preferences_controller.dart';
import 'package:convenia_mobile/widgets/scope_note.dart';
import 'package:flutter_test/flutter_test.dart';

SupermarketCoverage _s(String code, String name, {required bool inRange}) => SupermarketCoverage(
  code: code,
  name: name,
  inRange: inRange,
  storesInRange: inRange ? 2 : 0,
  nearestKm: inRange ? 1.0 : null,
);

void main() {
  test('joinNames une con comas y "y"', () {
    expect(joinNames([]), '');
    expect(joinNames(['D1']), 'D1');
    expect(joinNames(['D1', 'Éxito']), 'D1 y Éxito');
    expect(joinNames(['D1', 'Éxito', 'Jumbo']), 'D1, Éxito y Jumbo');
  });

  group('CoverageController', () {
    test('sin saber la cobertura no filtra ni muestra aviso', () {
      final c = CoverageController();
      expect(c.scope, isNull);
      expect(rangeSummary(c), isNull);
    });

    test('con cobertura, el alcance son sólo los supermercados en rango', () {
      final c = CoverageController()
        ..status = CoverageStatus.ready
        ..radiusKm = 5
        ..supermarkets = [
          _s('D1', 'D1', inRange: true),
          _s('EXITO', 'Éxito', inRange: true),
          _s('OLIMPICA', 'Olímpica', inRange: false),
        ];

      expect(c.scope, ['D1', 'EXITO']);
      // En las pantallas de precios no se nombra lo que queda fuera de rango...
      expect(rangeSummary(c), 'Solo tiendas a menos de 5 km: D1 y Éxito.');
      // ...pero al configurar la distancia sí.
      expect(
        rangeSummary(c, includeOutside: true),
        'Solo tiendas a menos de 5 km: D1 y Éxito. Fuera de tu rango: Olímpica.',
      );
    });

    test('si todo está en rango no menciona lo que queda fuera', () {
      final c = CoverageController()
        ..status = CoverageStatus.ready
        ..radiusKm = 10
        ..supermarkets = [_s('D1', 'D1', inRange: true)];

      expect(rangeSummary(c), 'Solo tiendas a menos de 10 km: D1.');
    });

    test('ningún supermercado en rango: alcance vacío y pide ampliar', () {
      final c = CoverageController()
        ..status = CoverageStatus.ready
        ..radiusKm = 1
        ..supermarkets = [_s('D1', 'D1', inRange: false)];

      expect(c.scope, isEmpty);
      expect(rangeSummary(c), contains('Amplía la distancia'));
    });

    test('sin ubicación no se filtra y se avisa', () {
      final c = CoverageController()
        ..status = CoverageStatus.unavailable
        ..problem = CoverageProblem.permission;

      expect(c.scope, isNull);
      expect(rangeSummary(c), contains('mostramos todos los supermercados'));
    });
  });

  group('ubicación elegida a mano', () {
    const bga = ManualLocation(latitude: 7.1193, longitude: -73.1227, label: 'Bucaramanga');

    test('dos ubicaciones con las mismas coordenadas son iguales aunque cambie la etiqueta', () {
      const otra = ManualLocation(latitude: 7.1193, longitude: -73.1227, label: 'Punto elegido en el mapa');
      expect(bga, otra);
    });

    test('al arrancar (eager: false) la registra sin consultar la red', () async {
      final c = CoverageController();

      await c.configure(radiusKm: 5, manual: bga, eager: false);

      expect(c.manualLocation, bga);
      expect(c.status, CoverageStatus.unknown);
      expect(c.scope, isNull);
    });

    test('quitarla vuelve a no saber la cobertura', () async {
      final c = CoverageController();
      await c.configure(radiusKm: 5, manual: bga, eager: false);

      await c.configure(radiusKm: 5, manual: null);

      expect(c.manualLocation, isNull);
      expect(c.status, CoverageStatus.unknown);
    });
  });
}
