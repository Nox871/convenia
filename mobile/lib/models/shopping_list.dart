/// Espejo de `app.schemas.shopping_list.ShoppingListItem`.
class ShoppingListItem {
  final int id;
  final String productId;
  final String name;
  final String? brand;
  final String? imageUrl;
  final int quantity;

  const ShoppingListItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.brand,
    required this.imageUrl,
    required this.quantity,
  });

  factory ShoppingListItem.fromJson(Map<String, dynamic> json) {
    return ShoppingListItem(
      id: json['id'] as int,
      productId: json['product_id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      imageUrl: json['image_url'] as String?,
      quantity: json['quantity'] as int,
    );
  }
}

/// Espejo de `app.schemas.shopping_list.ShoppingListSummary`.
class ShoppingListSummary {
  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int itemsCount;
  final int? budget;

  const ShoppingListSummary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.itemsCount,
    this.budget,
  });

  factory ShoppingListSummary.fromJson(Map<String, dynamic> json) {
    return ShoppingListSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      itemsCount: json['items_count'] as int,
      budget: json['budget'] as int?,
    );
  }
}

/// Espejo de `app.schemas.shopping_list.ShoppingListDetail`.
class ShoppingListDetail {
  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? budget;
  final List<ShoppingListItem> items;

  const ShoppingListDetail({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.budget,
  });

  factory ShoppingListDetail.fromJson(Map<String, dynamic> json) {
    return ShoppingListDetail(
      id: json['id'] as int,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      budget: json['budget'] as int?,
      items: (json['items'] as List<dynamic>)
          .map((e) => ShoppingListItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Espejo de `app.schemas.shopping_list.SupermarketCost`.
class SupermarketCost {
  final String supermarketCode;
  final String supermarketName;
  final double? totalCost;
  final int itemsPriced;
  final int itemsTotal;
  final bool isComplete;

  /// Ids de los ítems de la lista que NO tienen precio en este supermercado.
  final List<int> missingItemIds;

  const SupermarketCost({
    required this.supermarketCode,
    required this.supermarketName,
    required this.totalCost,
    required this.itemsPriced,
    required this.itemsTotal,
    required this.isComplete,
    this.missingItemIds = const [],
  });

  factory SupermarketCost.fromJson(Map<String, dynamic> json) {
    return SupermarketCost(
      supermarketCode: json['supermarket_code'] as String,
      supermarketName: json['supermarket_name'] as String,
      totalCost: (json['total_cost'] as num?)?.toDouble(),
      itemsPriced: json['items_priced'] as int,
      itemsTotal: json['items_total'] as int,
      isComplete: json['is_complete'] as bool,
      missingItemIds: (json['missing_item_ids'] as List<dynamic>? ?? const []).cast<int>(),
    );
  }
}

/// Espejo de `app.schemas.shopping_list.ShoppingListCostResponse`.
class ShoppingListCostResponse {
  final int listId;
  final List<SupermarketCost> costs;
  final String? bestSupermarketCode;

  const ShoppingListCostResponse({
    required this.listId,
    required this.costs,
    required this.bestSupermarketCode,
  });

  factory ShoppingListCostResponse.fromJson(Map<String, dynamic> json) {
    return ShoppingListCostResponse(
      listId: json['list_id'] as int,
      costs: (json['costs'] as List<dynamic>)
          .map((e) => SupermarketCost.fromJson(e as Map<String, dynamic>))
          .toList(),
      bestSupermarketCode: json['best_supermarket_code'] as String?,
    );
  }
}

/// Espejo de `app.schemas.shopping_list.DistributedPlanItem`.
class DistributedPlanItem {
  final int itemId;
  final String name;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  const DistributedPlanItem({
    required this.itemId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory DistributedPlanItem.fromJson(Map<String, dynamic> json) {
    return DistributedPlanItem(
      itemId: json['item_id'] as int,
      name: json['name'] as String,
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }
}

/// Espejo de `app.schemas.shopping_list.DistributedPlanStop`.
class DistributedPlanStop {
  final String supermarketCode;
  final String supermarketName;
  final List<DistributedPlanItem> items;
  final double subtotal;

  const DistributedPlanStop({
    required this.supermarketCode,
    required this.supermarketName,
    required this.items,
    required this.subtotal,
  });

  factory DistributedPlanStop.fromJson(Map<String, dynamic> json) {
    return DistributedPlanStop(
      supermarketCode: json['supermarket_code'] as String,
      supermarketName: json['supermarket_name'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => DistributedPlanItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }
}

/// Espejo de `app.schemas.shopping_list.ShoppingListDistributedResponse`.
class ShoppingListDistributedResponse {
  final int listId;
  final double? totalCost;
  final List<DistributedPlanStop> stops;
  final List<int> unpricedItemIds;

  const ShoppingListDistributedResponse({
    required this.listId,
    required this.totalCost,
    required this.stops,
    required this.unpricedItemIds,
  });

  factory ShoppingListDistributedResponse.fromJson(Map<String, dynamic> json) {
    return ShoppingListDistributedResponse(
      listId: json['list_id'] as int,
      totalCost: (json['total_cost'] as num?)?.toDouble(),
      stops: (json['stops'] as List<dynamic>)
          .map((e) => DistributedPlanStop.fromJson(e as Map<String, dynamic>))
          .toList(),
      unpricedItemIds: (json['unpriced_item_ids'] as List<dynamic>).cast<int>(),
    );
  }
}
