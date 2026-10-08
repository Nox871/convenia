import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/price_offer.dart';
import 'price_with_discount.dart';
import 'supermarket_badge.dart';

/// Fila de una oferta dentro de "Disponibilidad"/"Precios registrados" del detalle.
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

    // No se muestra la fecha del dato: el precio que se ve es siempre el último conocido.
    final unavailable = offer.available == false;

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
                if (unavailable)
                  const Text('No disponible actualmente', style: TextStyle(fontSize: 12, color: AppColors.error)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PriceWithDiscount(
                label: formatCop(offer.price!),
                price: offer.price!,
                listPrice: offer.listPrice,
                muted: true, // ya dentro del producto, el precio anterior no debe llamar la atención
                style: AppText.priceCard.copyWith(color: isBest ? AppColors.success : AppColors.ink),
              ),
              // Sin precio por kilo/litro: aquí se comparan tiendas para el MISMO producto y
              // tamaño, así que ese número es proporcional al precio y sólo confundía.
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
}
