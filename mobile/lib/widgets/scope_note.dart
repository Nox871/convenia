import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/coverage_controller.dart';
import '../screens/pick_location_screen.dart';
import '../state/preferences_controller.dart';

String joinNames(List<String> names) {
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
}

String _km(double km) => '${km.toStringAsFixed(0)} km';

/// Frase que resume qué supermercados están al alcance, o `null` mientras
/// todavía no se sabe.
///
/// Con `includeOutside` también nombra los supermercados que quedan fuera del
/// rango (útil al configurar la distancia; en las pantallas de precios es
/// ruido: no hay dónde comprar ahí).
String? rangeSummary(CoverageController coverage, {bool includeOutside = false}) {
  switch (coverage.status) {
    case CoverageStatus.unknown:
      return null;
    case CoverageStatus.unavailable:
      return switch (coverage.problem) {
        CoverageProblem.gpsOff => 'Con la ubicación apagada no podemos limitar a tiendas cercanas: '
            'mostramos todos los supermercados.',
        CoverageProblem.permission => 'Sin permiso de ubicación no podemos limitar a tiendas cercanas: '
            'mostramos todos los supermercados.',
        _ => 'No pudimos ubicarte para limitar a tiendas cercanas: mostramos todos los supermercados.',
      };
    case CoverageStatus.ready:
      final near = coverage.inRange.map((s) => s.name).toList();
      final far = coverage.outOfRange.map((s) => s.name).toList();
      if (near.isEmpty) {
        return 'Ningún supermercado tiene tiendas a menos de ${_km(coverage.radiusKm)} de ti. '
            'Amplía la distancia para ver precios.';
      }
      final base = 'Solo tiendas a menos de ${_km(coverage.radiusKm)}: ${joinNames(near)}.';
      return (!includeOutside || far.isEmpty) ? base : '$base Fuera de tu rango: ${joinNames(far)}.';
  }
}

/// Selector de distancia máxima + resumen de qué queda al alcance. Se usa en
/// Perfil y en la hoja que se abre desde el aviso de rango.
class RangePanel extends StatelessWidget {
  /// Se llama después de que la cobertura se recalculó con la nueva distancia.
  final VoidCallback? onChanged;

  const RangePanel({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesController>();
    final coverage = context.watch<CoverageController>();
    final summary = rangeSummary(coverage, includeOutside: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final km in PreferencesController.distanceOptionsKm)
              ChoiceChip(
                label: Text(_km(km)),
                selected: prefs.maxDistanceKm == km,
                onSelected: (_) async {
                  await prefs.setMaxDistanceKm(km);
                  await coverage.setRadius(km);
                  onChanged?.call();
                },
              ),
          ],
        ),
        if (summary != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(summary, style: AppText.caption),
        ],
        if (coverage.status == CoverageStatus.unavailable) ...[
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: () async {
              final picked = await Navigator.of(context).push<ManualLocation>(
                MaterialPageRoute(builder: (_) => PickLocationScreen(initial: prefs.manualLocation)),
              );
              if (picked == null) return;
              await prefs.setManualLocation(picked);
              await coverage.configure(radiusKm: prefs.maxDistanceKm, manual: picked);
              onChanged?.call();
            },
            child: const Text('Elegir mi ubicación'),
          ),
          TextButton(
            onPressed: () async {
              if (coverage.problem == CoverageProblem.permission) {
                await Geolocator.openAppSettings();
              } else if (coverage.problem == CoverageProblem.gpsOff) {
                await Geolocator.openLocationSettings();
              }
              await coverage.refresh();
              onChanged?.call();
            },
            child: const Text('Activar ubicación'),
          ),
        ],
      ],
    );
  }
}

/// Aviso corto sobre el rango con el que se están comparando precios; al
/// tocarlo se puede cambiar la distancia sin salir de la pantalla.
class ScopeNote extends StatelessWidget {
  final VoidCallback? onChanged;

  /// `false` cuando la pantalla que lo contiene ya tiene su propio margen.
  final bool padded;

  const ScopeNote({super.key, this.onChanged, this.padded = true});

  @override
  Widget build(BuildContext context) {
    final coverage = context.watch<CoverageController>();
    final summary = rangeSummary(coverage);
    if (summary == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padded ? AppSpacing.horizontalPage : 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (sheetContext) => Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Distancia máxima a las tiendas', style: AppText.screenTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Solo se comparan los supermercados que tienen una tienda dentro de esta distancia.',
                  style: AppText.body,
                ),
                const SizedBox(height: AppSpacing.lg),
                RangePanel(onChanged: onChanged),
              ],
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.lavenderMist,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Row(
            children: [
              const Icon(Icons.near_me_outlined, size: 18, color: AppColors.brandIndigo),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(summary, style: AppText.caption.copyWith(color: AppColors.ink))),
              const Icon(Icons.tune_rounded, size: 18, color: AppColors.brandIndigo),
            ],
          ),
        ),
      ),
    );
  }
}
