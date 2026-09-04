import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Chip de color de marca para identificar de un vistazo a qué supermercado
/// pertenece un precio (rojo D1 / ámbar Éxito).
class SupermarketBadge extends StatelessWidget {
  final String code;
  final String name;

  const SupermarketBadge({super.key, required this.code, required this.name});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forSupermarket(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      ),
      child: Text(
        name,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
