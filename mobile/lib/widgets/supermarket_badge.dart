import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Chip neutral que identifica de un vistazo a qué supermercado pertenece un
/// precio -- por NOMBRE, nunca por color. Los supermercados se mantienen
/// visualmente neutrales entre sí: introducir un color por tienda rompería
/// la identidad de marca de Convenia y además dejaría de escalar cuando se
/// agreguen más fuentes.
class SupermarketBadge extends StatelessWidget {
  final String code;
  final String name;

  const SupermarketBadge({super.key, required this.code, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.lavenderMist,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      ),
      child: Text(
        name,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
    );
  }
}
