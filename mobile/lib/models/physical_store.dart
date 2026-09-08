/// Espejo de `app.schemas.store.PhysicalStore`.
class PhysicalStore {
  final int id;
  final String supermarketCode;
  final String supermarketName;
  final String name;
  final String? address;
  final String? city;
  final double? latitude;
  final double? longitude;

  const PhysicalStore({
    required this.id,
    required this.supermarketCode,
    required this.supermarketName,
    required this.name,
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  factory PhysicalStore.fromJson(Map<String, dynamic> json) {
    return PhysicalStore(
      id: json['id'] as int,
      supermarketCode: json['supermarket_code'] as String,
      supermarketName: json['supermarket_name'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      city: json['city'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// Espejo de `app.schemas.store.NearbyStore` (PhysicalStore + distancia).
class NearbyStore extends PhysicalStore {
  final double distanceKm;
  final int walkingMinutes;

  const NearbyStore({
    required super.id,
    required super.supermarketCode,
    required super.supermarketName,
    required super.name,
    required super.address,
    required super.city,
    required super.latitude,
    required super.longitude,
    required this.distanceKm,
    required this.walkingMinutes,
  });

  factory NearbyStore.fromJson(Map<String, dynamic> json) {
    return NearbyStore(
      id: json['id'] as int,
      supermarketCode: json['supermarket_code'] as String,
      supermarketName: json['supermarket_name'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      city: json['city'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num).toDouble(),
      walkingMinutes: json['walking_minutes'] as int,
    );
  }
}
