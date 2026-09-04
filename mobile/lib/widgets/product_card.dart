import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/product_list_item.dart';
import 'product_image.dart';
import 'supermarket_badge.dart';

/// Tarjeta de producto en la lista de Resultados.
///
/// Nota de diseño importante: `GET /api/products` devuelve HOY una fila por
/// `source_product` de UN solo supermercado (no hay homologación todavía),
/// así que esta tarjeta muestra el precio real disponible para ESE
/// supermercado — nunca fabrica un precio para el otro. La comparación
/// "D1 vs Éxito" con ahorro y ganador se muestra en la pantalla de
/// Detalle/Comparación, que sí consulta `/compare` por producto.
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
          border: Border.all(color: AppColors.slate100),
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
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: 4,
                    children: [
                      SupermarketBadge(code: item.supermarketCode, name: item.supermarketName),
                      if (item.price != null) ...[
                        Text(formatCop(item.price!), style: AppText.priceCard),
                        if (hasDiscount)
                          Text(
                            formatCop(item.listPrice!),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate400,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ] else
                        const Text('Precio no disponible', style: AppText.caption),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.slate400),
          ],
        ),
      ),
    );
  }
}
