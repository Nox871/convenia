import 'package:flutter/material.dart';

/// Cómo se va a llegar a una tienda. Los tiempos son estimaciones: distancia en
/// línea recta (que ya trae el servidor) por un factor de calles, entre la
/// velocidad media urbana de cada medio. No usan el tráfico real.
enum TravelMode {
  walking('A pie', Icons.directions_walk_rounded, 5, 'walking'),
  bicycle('Bicicleta', Icons.directions_bike_rounded, 15, 'bicycling'),
  motorbike('Moto', Icons.two_wheeler_rounded, 25, 'two-wheeler'),
  car('Carro', Icons.directions_car_rounded, 20, 'driving');

  final String label;
  final IconData icon;

  /// Velocidad media en ciudad (km/h).
  final double speedKmh;

  /// Valor de `travelmode` de Google Maps.
  final String googleMode;

  const TravelMode(this.label, this.icon, this.speedKmh, this.googleMode);

  /// Una calle real es más larga que la línea recta entre dos puntos.
  static const streetFactor = 1.25;

  /// Minutos estimados para una distancia en línea recta (mínimo 1).
  int minutesFor(double straightLineKm) {
    final minutes = straightLineKm * streetFactor / speedKmh * 60;
    return minutes < 1 ? 1 : minutes.round();
  }

  /// "5 min", "1 h 05 min".
  String durationLabel(double straightLineKm) {
    final m = minutesFor(straightLineKm);
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rest = m % 60;
    return rest == 0 ? '$h h' : '$h h ${rest.toString().padLeft(2, '0')} min';
  }

  static TravelMode fromName(String? name) =>
      TravelMode.values.firstWhere((m) => m.name == name, orElse: () => TravelMode.walking);
}
