import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/price_offer.dart';
import 'supermarket_badge.dart';

/// Fila de una oferta dentro de la lista "todas las ofertas" del detalle.
/// `isBest` resalta visualmente la oferta ganadora (verde), igual que en las
/// tarjetas de resultados. Cuando la oferta no tiene datos (`!offer.hasData`)
/// se muestra "Sin datos" en vez de un precio — nunca $0.
class PriceOfferTile extends StatelessWidget {
  final PriceOffer offer;
  final bool isBest;

  const PriceOfferTile({super.key, required this.offer, required this.isBest});

  @override
  Widget build(BuildContext context) {
    if (!offer.hasData) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.mist,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.mist),
        ),
        child: Row(
          children: [
            SupermarketBadge(code: offer.supermarketCode, name: offer.supermarketName),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('Sin datos', style: AppText.caption),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isBest ? AppColors.successSurface : AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: isBest ? AppColors.successBorder : AppColors.mist),
      ),
      child: Row(
        children: [
          SupermarketBadge(code: offer.supermarketCode, name: offer.supermarketName),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Observado el ${_formatDate(offer.observedAt!)}',
                        style: AppText.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (offer.isStale) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.schedule_rounded, size: 12, color: AppColors.inkFaint),
                    ],
                  ],
                ),
                if (offer.isStale)
                  const Text(
                    'Dato desactualizado',
                    style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                  ),
                if (offer.available == false)
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
                formatCop(offer.price!),
                style: AppText.priceCard.copyWith(
                  color: isBest ? AppColors.success : AppColors.ink,
                ),
              ),
              if (offer.unitPrice != null && offer.unitLabel != null)
                Text(
                  '${formatCop(offer.unitPrice!)} ${offer.unitLabel}',
                  style: AppText.caption,
                ),
              if (offer.listPrice != null && offer.listPrice! > offer.price!)
                Text(
                  formatCop(offer.listPrice!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkFaint,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ],
          ),
          if (isBest) ...[
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
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
