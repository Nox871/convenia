import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Imagen de producto con placeholder seguro: si `imageUrl` es null, está
/// vacío, o falla la carga, nunca rompe el layout — muestra un ícono neutro
/// conservando toda la información textual del producto alrededor.
class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final double radius;

  /// Llena el alto disponible (la tarjeta decide el alto) en vez de ser cuadrada.
  /// [size] pasa a ser el ancho.
  final bool fillHeight;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.size = 72,
    this.radius = 12,
    this.fillHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: fillHeight ? double.infinity : size,
        // Las fotos de producto traen fondo blanco: sobre marfil se veían franjas
        // arriba y abajo cuando la imagen llena el alto de la tarjeta.
        color: fillHeight ? AppColors.white : AppColors.softIvory,
        child: (url == null || url.isEmpty)
            ? _placeholder()
            : Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _placeholder(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _placeholder(loading: true);
                },
              ),
      ),
    );
  }

  Widget _placeholder({bool loading = false}) {
    return Center(
      child: Icon(
        loading ? Icons.image_outlined : Icons.shopping_bag_outlined,
        color: AppColors.inkFaint,
        size: size * 0.4,
      ),
    );
  }
}
