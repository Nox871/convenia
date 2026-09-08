/// Espejo de `app.schemas.supermarket.Supermarket`.
class Supermarket {
  final int id;
  final String code;
  final String name;
  final String? websiteUrl;
  final String currency;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastSuccessfulRunAt;

  const Supermarket({
    required this.id,
    required this.code,
    required this.name,
    required this.websiteUrl,
    required this.currency,
    required this.isActive,
    required this.createdAt,
    required this.lastSuccessfulRunAt,
  });

  factory Supermarket.fromJson(Map<String, dynamic> json) {
    return Supermarket(
      id: json['id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      websiteUrl: json['website_url'] as String?,
      currency: json['currency'] as String,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastSuccessfulRunAt: json['last_successful_run_at'] == null
          ? null
          : DateTime.parse(json['last_successful_run_at'] as String),
    );
  }
}
