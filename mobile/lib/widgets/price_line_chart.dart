import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/price_trend.dart';
import '../core/theme.dart';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _fechaCorta(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

/// Evolución del precio día a día (una línea, un punto por día). Se puede tocar
/// o arrastrar para ver el precio de cada fecha. Si hay una proyección, se
/// dibuja punteada a continuación de la línea real.
class PriceLineChart extends StatefulWidget {
  final List<DailyPrice> series; // de la más antigua a la más reciente
  final List<DailyPrice> projection;
  final double height;

  const PriceLineChart({
    super.key,
    required this.series,
    this.projection = const [],
    this.height = 190,
  });

  @override
  State<PriceLineChart> createState() => _PriceLineChartState();
}

class _PriceLineChartState extends State<PriceLineChart> {
  int? _selected;

  void _select(Offset local, double width) {
    final series = widget.series;
    if (series.isEmpty) return;
    final geometry = _ChartGeometry(series, widget.projection, Size(width, widget.height));
    var mejor = 0;
    var distancia = double.infinity;
    for (var i = 0; i < series.length; i++) {
      final d = (geometry.x(series[i].day) - local.dx).abs();
      if (d < distancia) {
        distancia = d;
        mejor = i;
      }
    }
    setState(() => _selected = mejor);
  }

  @override
  void didUpdateWidget(covariant PriceLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != null && _selected! >= widget.series.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.series.isEmpty) return SizedBox(height: widget.height);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _select(d.localPosition, width),
          onHorizontalDragUpdate: (d) => _select(d.localPosition, width),
          child: CustomPaint(
            size: Size(width, widget.height),
            painter: _LineChartPainter(
              series: widget.series,
              projection: widget.projection,
              selected: _selected,
            ),
          ),
        );
      },
    );
  }
}

/// Convierte fechas y precios en coordenadas del lienzo.
class _ChartGeometry {
  static const left = 6.0, right = 10.0, top = 30.0, bottom = 24.0;

  final List<DailyPrice> series;
  final List<DailyPrice> projection;
  final Size size;
  late final DateTime t0;
  late final int totalDays;
  late final double minY;
  late final double maxY;

  _ChartGeometry(this.series, this.projection, this.size) {
    t0 = series.first.day;
    final fin = projection.isNotEmpty ? projection.last.day : series.last.day;
    totalDays = math.max(1, fin.difference(t0).inDays);
    final valores = [...series.map((p) => p.price), ...projection.map((p) => p.price)];
    var lo = valores.reduce(math.min);
    var hi = valores.reduce(math.max);
    final margen = (hi - lo) == 0 ? math.max(50.0, hi * 0.05) : (hi - lo) * 0.18;
    lo = math.max(0, lo - margen);
    hi = hi + margen;
    minY = lo;
    maxY = hi;
  }

  double get plotWidth => size.width - left - right;
  double get plotHeight => size.height - top - bottom;

  double x(DateTime d) {
    if (series.length == 1 && projection.isEmpty) return left + plotWidth / 2;
    return left + d.difference(t0).inDays / totalDays * plotWidth;
  }

  double y(double price) => top + (1 - (price - minY) / (maxY - minY)) * plotHeight;
}

class _LineChartPainter extends CustomPainter {
  final List<DailyPrice> series;
  final List<DailyPrice> projection;
  final int? selected;

  _LineChartPainter({required this.series, required this.projection, required this.selected});

  void _text(Canvas canvas, String text, Offset at,
      {Color color = AppColors.inkFaint, double size = 10.5, bool bold = false, bool centered = false, bool rightAligned = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (centered) dx -= tp.width / 2;
    if (rightAligned) dx -= tp.width;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, math.min(distance + 6, metric.length)), paint);
        distance += 11;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = _ChartGeometry(series, projection, size);

    // Rejilla y etiquetas de precio (mínimo, medio y máximo del eje).
    final grid = Paint()
      ..color = AppColors.mist
      ..strokeWidth = 1;
    for (final fraccion in const [0.0, 0.5, 1.0]) {
      final precio = g.minY + (g.maxY - g.minY) * fraccion;
      final yy = g.y(precio);
      canvas.drawLine(Offset(_ChartGeometry.left, yy), Offset(size.width - _ChartGeometry.right, yy), grid);
      _text(canvas, formatCop(precio), Offset(_ChartGeometry.left + 2, yy - 13));
    }

    final puntos = [for (final p in series) Offset(g.x(p.day), g.y(p.price))];

    // Área bajo la línea.
    if (puntos.length > 1) {
      final area = Path()..moveTo(puntos.first.dx, g.y(g.minY));
      for (final p in puntos) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(puntos.last.dx, g.y(g.minY))
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.brandIndigo.withValues(alpha: 0.18), AppColors.brandIndigo.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, g.y(g.maxY), size.width, g.plotHeight)),
      );

      final linea = Path()..moveTo(puntos.first.dx, puntos.first.dy);
      for (final p in puntos.skip(1)) {
        linea.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        linea,
        Paint()
          ..color = AppColors.brandIndigo
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // Proyección: punteada, a continuación del último punto real.
    if (projection.isNotEmpty) {
      final trazo = Path()..moveTo(puntos.last.dx, puntos.last.dy);
      for (final p in projection) {
        trazo.lineTo(g.x(p.day), g.y(p.price));
      }
      _dashed(
        canvas,
        trazo,
        Paint()
          ..color = AppColors.brandIndigo.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
      final fin = Offset(g.x(projection.last.day), g.y(projection.last.price));
      canvas.drawCircle(fin, 4, Paint()..color = AppColors.white);
      canvas.drawCircle(
        fin,
        4,
        Paint()
          ..color = AppColors.brandIndigo.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _text(canvas, '~${formatCop(projection.last.price)}', Offset(fin.dx, fin.dy - 17),
          color: AppColors.brandIndigo, bold: true, rightAligned: true);
    }

    // Puntos reales (si no son demasiados) y el precio mínimo destacado.
    final menor = series.indexWhere((p) => p.price == series.map((x) => x.price).reduce(math.min));
    if (series.length <= 31) {
      for (final p in puntos) {
        canvas.drawCircle(p, 3, Paint()..color = AppColors.white);
        canvas.drawCircle(
          p,
          3,
          Paint()
            ..color = AppColors.brandIndigo
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      }
    }
    if (series.length > 1) {
      canvas.drawCircle(puntos[menor], 5.5, Paint()..color = AppColors.success);
      canvas.drawCircle(puntos[menor], 2.4, Paint()..color = AppColors.white);
    }
    final ultimo = puntos.last;
    canvas.drawCircle(ultimo, 6, Paint()..color = AppColors.brandIndigo.withValues(alpha: 0.2));
    canvas.drawCircle(ultimo, 4, Paint()..color = AppColors.brandIndigo);

    // Fechas del eje horizontal.
    final y = size.height - 16;
    _text(canvas, _fechaCorta(series.first.day), Offset(_ChartGeometry.left, y));
    if (series.length > 1 || projection.isNotEmpty) {
      final fin = projection.isNotEmpty ? projection.last.day : series.last.day;
      _text(canvas, _fechaCorta(fin), Offset(size.width - _ChartGeometry.right, y), rightAligned: true);
      if (projection.isNotEmpty) {
        _text(canvas, _fechaCorta(series.last.day), Offset(g.x(series.last.day), y), centered: true);
      }
    }

    // Selección: guía vertical y burbuja con fecha y precio.
    if (selected != null && selected! < series.length) {
      final p = series[selected!];
      final o = puntos[selected!];
      canvas.drawLine(
        Offset(o.dx, g.y(g.maxY)),
        Offset(o.dx, g.y(g.minY)),
        Paint()
          ..color = AppColors.brandIndigo.withValues(alpha: 0.35)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(o, 6, Paint()..color = AppColors.brandIndigo);
      canvas.drawCircle(o, 2.5, Paint()..color = AppColors.white);

      final etiqueta = '${_fechaCorta(p.day)} · ${formatCop(p.price)}';
      final tp = TextPainter(
        text: TextSpan(
          text: etiqueta,
          style: const TextStyle(color: AppColors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = tp.width + 16, h = tp.height + 8;
      var left = o.dx - w / 2;
      left = left.clamp(0.0, size.width - w);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, 2, w, h), const Radius.circular(8));
      canvas.drawRRect(rect, Paint()..color = AppColors.ink);
      tp.paint(canvas, Offset(left + 8, 6));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.series != series || old.projection != projection || old.selected != selected;
}
