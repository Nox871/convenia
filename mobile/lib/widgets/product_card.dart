import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/product_list_item.dart';
import 'price_with_discount.dart';
import 'product_image.dart';

/// Tarjeta de producto en la lista de Resultados.
///
/// Arriba: imagen + marca, nombre y presentación. Abajo, a todo el ancho (así
/// no queda un hueco bajo la imagen): el precio una sola vez y las tiendas que
/// lo tienen como etiquetas, la más barata en verde y las demás apagadas. Un
/// precio tachado, si lo hay, va en rojo: ya no es el precio vigente.
class ProductCard extends StatelessWidget {
  final ProductListItem item;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final presentation = extractPresentation(item.name);
    final rawBrand = (item.brand ?? '').trim();
    // "Sin marca" no es una marca: no ocupa una línea.
    final brand = const {'sin marca', 'sinmarca', 'generico', 'genérico', 's/m', 'n/a'}.contains(rawBrand.toLowerCase())
        ? ''
        : rawBrand;

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
        // La imagen ocupa TODO el alto de la tarjeta (a la izquierda) y el texto va
        // a su lado: así no queda un hueco bajo la imagen cuando el texto es largo.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProductImage(imageUrl: item.imageUrl, size: 96, fillHeight: true),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (brand.isNotEmpty)
                      Text(
                        brand.toUpperCase(),
                        style: AppText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      item.name,
                      style: AppText.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (presentation != null && !item.name.toLowerCase().contains(presentation.toLowerCase())) ...[
                      const SizedBox(height: 2),
                      Text(presentation, style: AppText.caption),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    if (item.price == null)
                      Text('Precio no disponible', style: AppText.caption)
                    else ...[
                      // El precio anterior (tachado) va chiquito, arriba a la derecha del
                      // precio real: informa el descuento sin competir con el precio de hoy.
                      PriceWithDiscount(
                        label: item.offers.length > 1 ? 'Desde ${formatCop(item.price!)}' : formatCop(item.price!),
                        price: item.price!,
                        listPrice: item.listPrice,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _StoreTags(item: item),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dónde se vende: el nombre de cada tienda, sin repetir el precio (ya está
/// arriba). La más barata en verde y las demás apagadas; con una sola tienda no
/// hay nada que comparar y la etiqueta queda neutra.
class _StoreTags extends StatelessWidget {
  final ProductListItem item;

  const _StoreTags({required this.item});

  @override
  Widget build(BuildContext context) {
    final offers = item.offers.isNotEmpty
        ? item.offers
        : [
            if (item.supermarketCode != null && item.supermarketName != null && item.price != null)
              StoreOffer(
                supermarketCode: item.supermarketCode!,
                supermarketName: item.supermarketName!,
                price: item.price!,
              ),
          ];
    if (offers.isEmpty) return const SizedBox.shrink();

    final compare = offers.length > 1;
    final cheapest = offers.first.price; // llegan ordenadas de menor a mayor
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final o in offers)
          _tag(o.supermarketName, best: compare && o.price <= cheapest, muted: compare && o.price > cheapest),
      ],
    );
  }

  Widget _tag(String name, {required bool best, required bool muted}) {
    final Color bg = best ? AppColors.successSurface : (muted ? AppColors.mist : AppColors.lavenderMist);
    final Color fg = best ? AppColors.success : (muted ? AppColors.inkFaint : AppColors.ink);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        border: best ? Border.all(color: AppColors.successBorder) : null,
      ),
      child: Text(name, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
