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
          border: Border.all(color: AppColors.mist),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// Chip de selección genérico (criterio de orden en Resultados, filtros
/// avanzados ocultos, etc.). El estado seleccionado usa `brandIndigo` -- la
/// única acción/selección activa de la pantalla, consistente con la regla
/// 80/15/5 de la identidad visual.
class FilterChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  const FilterChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandIndigo : AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          border: Border.all(color: selected ? AppColors.brandIndigo : AppColors.mist),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? AppColors.white
                : (enabled ? AppColors.inkMuted : AppColors.inkFaint),
          ),
        ),
      ),
    );
  }
}
