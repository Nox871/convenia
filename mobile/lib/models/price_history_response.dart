import 'page_info.dart';

/// Espejo de `app.schemas.price.PriceHistoryPoint`.
class PriceHistoryPoint {
  final double price;
  final double? listPrice;
  final String currency;
  final bool available;
  final DateTime observedAt;

  const PriceHistoryPoint({
    required this.price,
    required this.listPrice,
    required this.currency,
    required this.available,
    required this.observedAt,
  });

  factory PriceHistoryPoint.fromJson(Map<String, dynamic> json) {
    return PriceHistoryPoint(
      price: (json['price'] as num).toDouble(),
      listPrice: (json['list_price'] as num?)?.toDouble(),
      currency: json['currency'] as String,
      available: json['available'] as bool,
      observedAt: DateTime.parse(json['observed_at'] as String),
    );
  }
}

/// Espejo de `app.schemas.price.PriceHistoryResponse`.
class PriceHistoryResponse {
  final String productId;
  final double minPrice;
  final double maxPrice;
  final double avgPrice;
  final double currentPrice;
  final DateTime currentObservedAt;
  final double variationPercentage;
  final int observationsCount;
  final List<PriceHistoryPoint> observations;
  final PageInfo pagination;

  const PriceHistoryResponse({
    required this.productId,
    required this.minPrice,
    required this.maxPrice,
    required this.avgPrice,
    required this.currentPrice,
    required this.currentObservedAt,
    required this.variationPercentage,
    required this.observationsCount,
    required this.observations,
    required this.pagination,
  });

  factory PriceHistoryResponse.fromJson(Map<String, dynamic> json) {
    return PriceHistoryResponse(
      productId: json['product_id'] as String,
      minPrice: (json['min_price'] as num).toDouble(),
      maxPrice: (json['max_price'] as num).toDouble(),
      avgPrice: (json['avg_price'] as num).toDouble(),
      currentPrice: (json['current_price'] as num).toDouble(),
      currentObservedAt: DateTime.parse(json['current_observed_at'] as String),
      variationPercentage: (json['variation_percentage'] as num).toDouble(),
      observationsCount: json['observations_count'] as int,
      observations: (json['observations'] as List<dynamic>)
          .map((e) => PriceHistoryPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      pagination: PageInfo.fromJson(json['pagination'] as Map<String, dynamic>),
    );
  }
}
