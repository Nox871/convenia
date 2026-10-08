import '../models/price_history_response.dart';

/// Un precio por día (el mejor del día entre las tiendas al alcance).
class DailyPrice {
  final DateTime day; // fecha local, sin hora
  final double price;

  const DailyPrice(this.day, this.price);
}

/// Colapsa las observaciones a UNA por día (hora local), quedándose con el
/// menor precio de ese día, y las ordena de la más antigua a la más reciente.
///
/// El servidor actual ya entrega un punto por día; esto es una defensa para
/// que la misma fecha nunca aparezca dos veces en el gráfico aunque llegue
/// una respuesta con varias observaciones del mismo día (API anterior, o
/// precios de varias tiendas el mismo día).
List<DailyPrice> toDailySeries(Iterable<PriceHistoryPoint> observations) {
  final porDia = <DateTime, double>{};
  for (final o in observations) {
    if (!o.available || o.price <= 0) continue;
    final local = o.observedAt.toLocal();
    final dia = DateTime(local.year, local.month, local.day);
    final actual = porDia[dia];
    if (actual == null || o.price < actual) porDia[dia] = o.price;
  }
  final dias = porDia.keys.toList()..sort();
  return [for (final d in dias) DailyPrice(d, porDia[d]!)];
}

enum TrendDirection { up, down, stable, unclear }

/// Estimación lineal de hacia dónde va el precio. Es una extrapolación simple
/// de lo observado, no una predicción: se calcula sólo con datos suficientes y
/// se descarta cuando los precios no siguen un patrón.
class TrendEstimate {
  final TrendDirection direction;

  /// Cambio estimado por semana, en % del precio medio de la ventana.
  final double weeklyPercent;

  /// Puntos proyectados (uno por día, hacia adelante). Vacío si `unclear`.
  final List<DailyPrice> projection;

  /// Cuánto de la variación explica la recta (0 a 1).
  final double fit;

  const TrendEstimate({
    required this.direction,
    required this.weeklyPercent,
    required this.projection,
    required this.fit,
  });
}

/// Mínimo de días con precio para estimar una tendencia: con menos, cualquier
/// recta "encaja" y sería inventar un patrón.
const minDaysForTrend = 7;

/// Recta de mínimos cuadrados sobre los últimos [window] días con datos y su
/// extensión [horizonDays] días hacia adelante. Devuelve null si hay menos de
/// [minDaysForTrend] puntos.
TrendEstimate? estimateTrend(
  List<DailyPrice> series, {
  int window = 14,
  int horizonDays = 7,
}) {
  if (series.length < minDaysForTrend) return null;
  final recientes = series.length > window ? series.sublist(series.length - window) : series;
  final origen = recientes.first.day;
  final xs = [for (final p in recientes) p.day.difference(origen).inDays.toDouble()];
  final ys = [for (final p in recientes) p.price];
  final n = xs.length;
  final mediaX = xs.reduce((a, b) => a + b) / n;
  final mediaY = ys.reduce((a, b) => a + b) / n;

  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mediaX) * (xs[i] - mediaX);
    sxy += (xs[i] - mediaX) * (ys[i] - mediaY);
    syy += (ys[i] - mediaY) * (ys[i] - mediaY);
  }
  if (sxx == 0) return null;

  final pendiente = sxy / sxx;
  final intercepto = mediaY - pendiente * mediaX;
  final fit = syy == 0 ? 1.0 : (sxy * sxy) / (sxx * syy);
  final semanal = mediaY == 0 ? 0.0 : pendiente * 7 / mediaY * 100;

  final TrendDirection direccion;
  if (semanal.abs() < 1) {
    direccion = TrendDirection.stable;
  } else if (fit < 0.25) {
    direccion = TrendDirection.unclear;
  } else {
    direccion = semanal > 0 ? TrendDirection.up : TrendDirection.down;
  }

  final proyeccion = <DailyPrice>[];
  if (direccion != TrendDirection.unclear) {
    final ultimo = recientes.last.day;
    final xUltimo = ultimo.difference(origen).inDays.toDouble();
    for (var d = 1; d <= horizonDays; d++) {
      final x = xUltimo + d;
      final y = (intercepto + pendiente * x).clamp(0, double.infinity).toDouble();
      proyeccion.add(DailyPrice(ultimo.add(Duration(days: d)), y));
    }
  }
  return TrendEstimate(
    direction: direccion,
    weeklyPercent: semanal,
    projection: proyeccion,
    fit: fit,
  );
}
