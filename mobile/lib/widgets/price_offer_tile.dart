import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/price_offer.dart';
import 'supermarket_badge.dart';

/// Fila de una oferta dentro de la lista "todas las ofertas" del detalle.
/// `isBest` resalta visualmente la oferta ganadora (verde), igual que en las
/// tarjetas de resultados.
class PriceOfferTile extends StatelessWidget {
  final PriceOffer offer;
  final bool isBest;

  const PriceOfferTile({super.key, required this.offer, required this.isBest});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isBest ? AppColors.bestPriceSurface : AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: isBest ? AppColors.bestPriceBorder : AppColors.slate100),
      ),
      child: Row(
        children: [
          SupermarketBadge(code: offer.supermarketCode, name: offer.supermarketName),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Observado el ${_formatDate(offer.observedAt)}',
                  style: AppText.caption,
                ),
                if (!offer.available)
                  const Text(
                    'No disponible actualmente',
                    style: TextStyle(fontSize: 11, color: AppColors.error),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatCop(offer.price),
                style: AppText.priceCard.copyWith(
                  color: isBest ? AppColors.bestPriceDark : AppColors.brandDark,
                ),
              ),
              if (offer.listPrice != null && offer.listPrice! > offer.price)
                Text(
                  formatCop(offer.listPrice!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate400,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ],
          ),
          if (isBest) ...[
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.check_circle_rounded, color: AppColors.bestPriceGreen, size: 18),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }
}
