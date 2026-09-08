import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/product_list_item.dart';
import 'product_image.dart';
import 'supermarket_badge.dart';

/// Tarjeta de producto en la lista de Resultados.
///
/// Un producto ya homologado (`offersCount > 1`) muestra "Desde {precio} en
/// N supermercados" -- el mejor precio conocido, sin insinuar que ese precio
/// aplica a todas las tiendas. Un producto todavía sin homologar
/// (`offersCount == 1`) muestra el precio real de su única tienda conocida,
/// sin lenguaje comparativo. La comparación completa vive en Detalle
/// (`/compare`).
class ProductCard extends StatelessWidget {
  final ProductListItem item;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final presentation = extractPresentation(item.name);
    final hasDiscount = item.listPrice != null &&
        item.price != null &&
        item.listPrice! > item.price!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.mist),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductImage(imageUrl: item.imageUrl),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.brand != null && item.brand!.isNotEmpty)
                    Text(
                      item.brand!.toUpperCase(),
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    item.name,
                    style: AppText.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (presentation != null) ...[
                    const SizedBox(height: 2),
                    Text(presentation, style: AppText.caption),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  if (item.offersCount > 1) ...[
                    Text(
                      'Desde ${item.price != null ? formatCop(item.price!) : '—'} '
                      'en ${item.offersCount} supermercados',
                      style: AppText.priceCard,
                    ),
                  ] else
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.sm,
                      runSpacing: 4,
                      children: [
                        if (item.supermarketCode != null && item.supermarketName != null)
                          SupermarketBadge(
                            code: item.supermarketCode!,
                            name: item.supermarketName!,
                          ),
                        if (item.price != null) ...[
                          Text(formatCop(item.price!), style: AppText.priceCard),
                          if (hasDiscount)
                            Text(
                              formatCop(item.listPrice!),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.inkFaint,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ] else
                          Text('Precio no disponible', style: AppText.caption),
                      ],
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
