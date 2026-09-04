import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Chip de "búsqueda frecuente" en Home (Leche, Arroz, Café, Huevos...).
/// Al tocarlo dispara una búsqueda real contra el backend.
class QuickSearchChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const QuickSearchChip({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          border: Border.all(color: AppColors.slate100),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.brandDark,
          ),
        ),
      ),
    );
  }
}

/// Chip de filtro en Resultados (Todos / Mejor en D1 / Mejor en Éxito).
class FilterChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FilterChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandDark : AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          border: Border.all(color: selected ? AppColors.brandDark : AppColors.slate100),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.white : AppColors.slate600,
          ),
        ),
      ),
    );
  }
}
