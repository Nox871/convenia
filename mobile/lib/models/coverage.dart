/// Espejo de `app.schemas.store.SupermarketCoverage`: si un supermercado tiene
/// tiendas dentro del rango de la persona.
class SupermarketCoverage {
  final String code;
  final String name;
  final bool inRange;
  final int storesInRange;
  final double? nearestKm;

  const SupermarketCoverage({
    required this.code,
    required this.name,
    required this.inRange,
    required this.storesInRange,
    required this.nearestKm,
  });

  factory SupermarketCoverage.fromJson(Map<String, dynamic> json) {
    return SupermarketCoverage(
      code: json['code'] as String,
      name: json['name'] as String,
      inRange: json['in_range'] as bool,
      storesInRange: json['stores_in_range'] as int,
      nearestKm: (json['nearest_km'] as num?)?.toDouble(),
    );
  }
}
