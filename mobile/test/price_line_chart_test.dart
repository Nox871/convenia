import 'dart:io';
import 'dart:ui' as ui;

import 'package:convenia_mobile/core/price_trend.dart';
import 'package:convenia_mobile/widgets/price_line_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

List<DailyPrice> _serie(List<double> precios, {int start = 1}) => [
      for (var i = 0; i < precios.length; i++) DailyPrice(DateTime(2026, 10, start + i), precios[i]),
    ];

Widget _app(Widget child, GlobalKey key) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              width: 380,
              child: child,
            ),
          ),
        ),
      ),
    );

Future<void> _guardar(WidgetTester tester, GlobalKey key, String nombre) async {
  final dir = Platform.environment['CHART_OUT'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$nombre.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('3 días de datos: línea sin proyección, y se puede tocar un punto', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(_app(PriceLineChart(series: _serie([2656, 2793, 2904])), key));
    await tester.tapAt(tester.getCenter(find.byType(PriceLineChart)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _guardar(tester, key, 'tres_dias');
  });

  testWidgets('14 días con tendencia al alza: línea real y proyección punteada', (tester) async {
    final key = GlobalKey();
    final real = _serie([2800, 2790, 2810, 2850, 2840, 2880, 2900, 2930, 2920, 2960, 2990, 3010, 3000, 3040]);
    final t = estimateTrend(real)!;
    await tester.pumpWidget(_app(PriceLineChart(series: real, projection: t.projection), key));
    expect(tester.takeException(), isNull);
    expect(t.direction, TrendDirection.up);
    await _guardar(tester, key, 'con_proyeccion');
  });

  testWidgets('un solo día y precio constante no rompen el gráfico', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(_app(PriceLineChart(series: _serie([1500])), key));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_app(PriceLineChart(series: _serie([1500, 1500, 1500])), key));
    expect(tester.takeException(), isNull);
    await _guardar(tester, key, 'constante');
  });
}
