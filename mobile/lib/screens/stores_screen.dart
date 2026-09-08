import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/nearby_stores_controller.dart';
import '../widgets/state_views.dart';

class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NearbyStoresController(),
      child: Scaffold(
        appBar: AppBar(title: Text('Establecimientos', style: AppText.screenTitle)),
        body: const SafeArea(child: _StoresBody()),
      ),
    );
  }
}

class _StoresBody extends StatelessWidget {
  const _StoresBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NearbyStoresController>();

    switch (controller.status) {
      case NearbyStoresStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case NearbyStoresStatus.permissionDenied:
        return _InfoPanel(
          icon: Icons.location_off_outlined,
          title: 'Ubicación no disponible',
          message: 'No concediste el permiso de ubicación. Puedes activarlo en los '
              'ajustes del sistema para ver los establecimientos más cercanos.',
          actionLabel: 'Abrir ajustes',
          onAction: Geolocator.openAppSettings,
          onRetry: controller.retry,
        );

      case NearbyStoresStatus.locationDisabled:
        return _InfoPanel(
          icon: Icons.location_disabled_rounded,
          title: 'GPS desactivado',
          message: 'Activa la ubicación de tu dispositivo para ver los '
              'establecimientos más cercanos.',
          actionLabel: 'Abrir ajustes de ubicación',
          onAction: Geolocator.openLocationSettings,
          onRetry: controller.retry,
        );

      case NearbyStoresStatus.timedOut:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gps_off_rounded, size: 48, color: AppColors.inkFaint),
                const SizedBox(height: AppSpacing.lg),
                Text('No pudimos ubicarte', style: AppText.screenTitle, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Obtener tu ubicación tomó demasiado tiempo. Verifica que el GPS '
                  'tenga buena señal e intenta de nuevo.',
                  style: AppText.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton(onPressed: controller.retry, child: const Text('Reintentar')),
              ],
            ),
          ),
        );

      case NearbyStoresStatus.error:
        return ErrorResultsView(onRetry: controller.retry);

      case NearbyStoresStatus.empty:
        return const EmptyResultsView(
          title: 'Sin establecimientos cercanos',
          message: 'Todavía no tenemos tiendas físicas registradas en tu zona.',
        );

      case NearbyStoresStatus.loaded:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.horizontalPage,
            AppSpacing.md,
            AppSpacing.horizontalPage,
            AppSpacing.xxxl,
          ),
          itemCount: controller.stores.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final store = controller.stores[index];
            return Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                border: Border.all(color: AppColors.mist),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.supermarketName, style: AppText.caption),
                        Text(store.name, style: AppText.productName),
                        if (store.address != null)
                          Text(store.address!, style: AppText.body),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${store.distanceKm.toStringAsFixed(1)} km',
                        style: AppText.priceCard.copyWith(fontSize: 14),
                      ),
                      Text('a pie: ~${store.walkingMinutes} min', style: AppText.caption),
                    ],
                  ),
                ],
              ),
            );
          },
        );
    }
  }
}

class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<bool> Function() onAction;
  final VoidCallback onRetry;

  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.inkFaint),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: AppText.screenTitle, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: AppText.body, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
