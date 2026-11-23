import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/compare_response.dart';
import '../models/price_offer.dart';

/// Tarjeta de comparación que se muestra sobre la cámara (módulo Convenia AR):
/// el más barato, el ahorro y el precio en cada supermercado.
///
/// Solo usa datos que entrega la API: no inventa precios ni ahorros, y avisa
/// cuando algún precio puede estar desactualizado.
class ArComparisonCard extends StatelessWidget {
  final CompareResponse data;
  final VoidCallback onAdd;
  final VoidCallback onClose;

  const ArComparisonCard({
    super.key,
    required this.data,
    required this.onAdd,
    required this.onClose,
  });

  List<PriceOffer> get _offers {
    final list = data.offers.where((o) => o.hasData).toList()
      ..sort((a, b) => a.price!.compareTo(b.price!));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final offers = _offers;
    final best = data.bestPrice ?? (offers.isEmpty ? null : offers.first);
    final maxPrice = offers.isEmpty ? 1.0 : offers.last.price!;
    final hasStale = offers.any((o) => o.isStale);
    final savingsAbs = data.savingsAbsolute;
    final savingsPct = data.savingsPercentage;

    return Container(
      key: const Key('ar_card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.product.name, style: AppText.productName, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          if (best == null)
            Text('Sin precios registrados para este producto.', style: AppText.body)
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Más barato: ', style: AppText.body.copyWith(color: AppColors.inkMuted)),
                Text(formatCop(best.price!), key: const Key('ar_best_price'), style: AppText.priceMain),
                Text('  en ${best.supermarketName}', style: AppText.body),
              ],
            ),
            if (savingsAbs != null && savingsAbs > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successSurface,
                  border: Border.all(color: AppColors.successBorder),
                  borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                ),
                child: Text(
                  'Ahorras ${formatCop(savingsAbs)}'
                  '${savingsPct == null ? '' : ' (${savingsPct < 1 ? 'menos de 1' : savingsPct.round()} %)'}'
                  ' frente al más caro',
                  key: const Key('ar_savings'),
                  style: AppText.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 10),
            for (final o in offers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 78, child: Text(o.supermarketName, style: AppText.caption.copyWith(color: AppColors.ink))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: o.price! / maxPrice,
                          minHeight: 7,
                          backgroundColor: AppColors.mist,
                          color: o.price == best.price ? AppColors.success : const Color(0xFFBDB8F5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: Text(formatCop(o.price!), textAlign: TextAlign.right, style: AppText.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            if (hasStale)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Algunos precios pueden estar desactualizados.', key: const Key('ar_stale'), style: AppText.caption.copyWith(color: AppColors.warning)),
              ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('ar_add'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brandIndigo),
                  onPressed: onAdd,
                  child: const Text('Agregar a la lista'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(key: const Key('ar_close'), onPressed: onClose, child: const Text('Escanear otro')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
