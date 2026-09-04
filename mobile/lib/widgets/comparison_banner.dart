import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/price_offer.dart';

/// Banner destacado de la pantalla de Comparación.
///
/// Solo afirma "te conviene comprarlo en X" cuando existen DOS OFERTAS REALES
/// que comparar (offers.length >= 2) — jamás cuando el producto solo tiene
/// precio en un supermercado, para no insinuar una comparación que no existe.
class ComparisonBanner extends StatelessWidget {
  final List<PriceOffer> offers;
  final PriceOffer? bestPrice;

  const ComparisonBanner({super.key, required this.offers, required this.bestPrice});

  @override
  Widget build(BuildContext context) {
    if (bestPrice == null || offers.isEmpty) {
      return _SingleStatePanel(
        icon: Icons.info_outline_rounded,
        color: AppColors.slate600,
        surface: AppColors.slate100,
        title: 'Sin precios disponibles',
        subtitle: 'Todavía no tenemos un precio vigente para este producto.',
      );
    }

    if (offers.length == 1) {
      final only = offers.first;
      return _SingleStatePanel(
        icon: Icons.storefront_outlined,
        color: AppColors.brandDark,
        surface: AppColors.slate100,
        title: 'Precio disponible en ${only.supermarketName}',
        subtitle:
            'Todavía no tenemos el precio de este producto en otro supermercado para comparar.',
        priceLabel: formatCop(only.price),
      );
    }

    final sorted = [...offers]..sort((a, b) => a.price.compareTo(b.price));
    final second = sorted.firstWhere(
      (o) => o.supermarketCode != bestPrice!.supermarketCode,
      orElse: () => sorted[1],
    );
    final savings = second.price - bestPrice!.price;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bestPriceSurface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.bestPriceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.bestPriceGreen, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Te conviene comprarlo en ${bestPrice!.supermarketName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.bestPriceDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(formatCop(bestPrice!.price), style: AppText.priceMain),
          const SizedBox(height: AppSpacing.sm),
          if (savings > 0)
            Text(
              'Puedes ahorrar ${formatCop(savings)} comprando en '
              '${bestPrice!.supermarketName} en lugar de ${second.supermarketName}.',
              style: const TextStyle(fontSize: 14, color: AppColors.bestPriceDark),
            )
          else
            Text(
              'Mismo precio en ${second.supermarketName}.',
              style: const TextStyle(fontSize: 14, color: AppColors.bestPriceDark),
            ),
        ],
      ),
    );
  }
}

class _SingleStatePanel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color surface;
  final String title;
  final String subtitle;
  final String? priceLabel;

  const _SingleStatePanel({
    required this.icon,
    required this.color,
    required this.surface,
    required this.title,
    required this.subtitle,
    this.priceLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          if (priceLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(priceLabel!, style: AppText.priceMain),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: AppText.body),
        ],
      ),
    );
  }
}
