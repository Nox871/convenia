import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/price_offer.dart';

/// Banner destacado de la pantalla de Comparación.
///
/// Solo afirma "te conviene comprarlo en X" cuando existen DOS OFERTAS REALES
/// que comparar (con dato de precio) — jamás cuando el producto solo tiene
/// precio en un supermercado, para no insinuar una comparación que no existe.
class ComparisonBanner extends StatelessWidget {
  final List<PriceOffer> offers;
  final PriceOffer? bestPrice;
  final bool isPartial;
  final double? savingsAbsolute;
  final double? savingsPercentage;

  const ComparisonBanner({
    super.key,
    required this.offers,
    required this.bestPrice,
    this.isPartial = false,
    this.savingsAbsolute,
    this.savingsPercentage,
  });

  @override
  Widget build(BuildContext context) {
    final conDatos = offers.where((o) => o.hasData).toList();

    if (bestPrice == null || conDatos.isEmpty) {
      return const _SingleStatePanel(
        icon: Icons.info_outline_rounded,
        color: AppColors.inkMuted,
        surface: AppColors.mist,
        title: 'Sin precios disponibles',
        subtitle: 'Todavía no tenemos un precio vigente para este producto.',
      );
    }

    if (conDatos.length == 1) {
      final only = conDatos.first;
      return _SingleStatePanel(
        icon: Icons.storefront_outlined,
        color: AppColors.ink,
        surface: AppColors.mist,
        title: 'Precio disponible en ${only.supermarketName}',
        subtitle:
            'Todavía no tenemos el precio de este producto en otro supermercado para comparar.',
        priceLabel: formatCop(only.price!),
      );
    }

    final sorted = [...conDatos]..sort((a, b) => a.price!.compareTo(b.price!));
    final second = sorted.firstWhere(
      (o) => o.supermarketCode != bestPrice!.supermarketCode,
      orElse: () => sorted[1],
    );
    final savings = savingsAbsolute ?? (second.price! - bestPrice!.price!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.successBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Te conviene comprarlo en ${bestPrice!.supermarketName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(formatCop(bestPrice!.price!), style: AppText.priceMain),
          const SizedBox(height: AppSpacing.sm),
          if (savings > 0)
            Text(
              'Puedes ahorrar ${formatCop(savings)}'
              '${savingsPercentage != null ? ' (${savingsPercentage!.toStringAsFixed(0)}%)' : ''} '
              'comprando en ${bestPrice!.supermarketName} en lugar de ${second.supermarketName}.',
              style: const TextStyle(fontSize: 14, color: AppColors.success),
            )
          else
            Text(
              'Mismo precio en ${second.supermarketName}.',
              style: const TextStyle(fontSize: 14, color: AppColors.success),
            ),
          if (isPartial) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.inkMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Comparación parcial: no todos los supermercados tienen datos de este producto.',
                    style: AppText.caption.copyWith(color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ],
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
