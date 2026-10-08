import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';

/// El precio real, grande, y —si hubo descuento— el precio anterior tachado,
/// chiquito y en rojo, arriba a la derecha del precio real, como un superíndice:
///
///     $1.490 ¹⁹⁰⁰   (el 1.900 va chico, arriba y a la derecha)
///
/// Informa el descuento sin importancia visual: lo que cuenta es el precio de hoy.
class PriceWithDiscount extends StatelessWidget {
  /// Texto del precio real (ej. "$1.490" o "Desde $1.490").
  final String label;

  /// Precio anterior; sólo se muestra si es mayor que [price].
  final double? listPrice;
  final double price;
  final TextStyle? style;

  /// Dentro del producto el descuento no debe robar protagonismo: va en gris y no en rojo.
  final bool muted;

  const PriceWithDiscount({
    super.key,
    required this.label,
    required this.price,
    this.listPrice,
    this.style,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = listPrice != null && listPrice! > price;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, // el precio anterior queda arriba
      children: [
        Flexible(child: Text(label, style: style ?? AppText.priceCard)),
        if (hasDiscount) ...[
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              formatCop(listPrice!),
              style: TextStyle(
                fontSize: 9,
                height: 1.1,
                color: muted ? AppColors.inkFaint : AppColors.error,
                decoration: TextDecoration.lineThrough,
                decorationColor: muted ? AppColors.inkFaint : AppColors.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
