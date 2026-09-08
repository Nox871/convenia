/// Espejo de `app.schemas.price.PriceHistoryMonthlyPoint`.
class PriceHistoryMonthlyPoint {
  final String month; // 'YYYY-MM'
  final double minPrice;
  final double maxPrice;
  final double avgPrice;
  final int observationsCount;

  const PriceHistoryMonthlyPoint({
    required this.month,
    required this.minPrice,
    required this.maxPrice,
    required this.avgPrice,
    required this.observationsCount,
  });

  factory PriceHistoryMonthlyPoint.fromJson(Map<String, dynamic> json) {
    return PriceHistoryMonthlyPoint(
      month: json['month'] as String,
      minPrice: (json['min_price'] as num).toDouble(),
      maxPrice: (json['max_price'] as num).toDouble(),
      avgPrice: (json['avg_price'] as num).toDouble(),
      observationsCount: json['observations_count'] as int,
    );
  }
}

/// Espejo de `app.schemas.price.PriceHistoryMonthlyResponse`.
class PriceHistoryMonthlyResponse {
  final String productId;
  final List<PriceHistoryMonthlyPoint> months;

  const PriceHistoryMonthlyResponse({required this.productId, required this.months});

  factory PriceHistoryMonthlyResponse.fromJson(Map<String, dynamic> json) {
    return PriceHistoryMonthlyResponse(
      productId: json['product_id'] as String,
      months: (json['months'] as List<dynamic>)
          .map((e) => PriceHistoryMonthlyPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
