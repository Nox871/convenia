import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/travel_mode.dart';
import '../models/physical_store.dart';
import '../state/auth_controller.dart';
import '../state/nearby_stores_controller.dart';
import '../state/preferences_controller.dart';
import '../widgets/state_views.dart';
import 'add_store_screen.dart';
import 'pick_location_screen.dart';

class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProxyProvider<PreferencesController, NearbyStoresController>(
      create: (context) => NearbyStoresController(
        nearRadiusKm: context.read<PreferencesController>().maxDistanceKm,
        manualLocation: context.read<PreferencesController>().manualLocation,
      ),
      update: (_, prefs, controller) => controller!
        ..configure(nearRadiusKm: prefs.maxDistanceKm, manual: prefs.manualLocation),
      child: Scaffold(
        appBar: AppBar(title: Text('Establecimientos', style: AppText.screenTitle)),
        body: const SafeArea(child: _StoresBody()),
        floatingActionButton: context.watch<AuthController>().isAdmin
            ? Builder(
                builder: (context) => FloatingActionButton.extended(
                  onPressed: () async {
                    final controller = context.read<NearbyStoresController>();
                    final added = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => AddStoreScreen(
                          initialLatitude: controller.userLatitude,
                          initialLongitude: controller.userLongitude,
                        ),
                      ),
                    );
                    if (added == true) controller.retry();
                  },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Agregar tienda'),
                ),
              )
            : null,
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
          onPickLocation: () => _pickManual(context, controller),
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
          onPickLocation: () => _pickManual(context, controller),
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
        final visible = controller.visibleStores;
        final chips = controller.availableSupermarkets;
        final missing = controller.supermarketsWithoutStores;
        return Column(
          children: [
            if (controller.radiusWasExpanded)
              _Notice(
                icon: Icons.info_outline_rounded,
                text: 'No hay tiendas registradas a menos de '
                    '${controller.nearRadiusKm.toStringAsFixed(0)} km de ti. '
                    'La más cercana está a ${controller.stores.first.distanceKm.toStringAsFixed(0)} km.',
              ),
            SizedBox(
              height: 260,
              child: _StoresMap(
                stores: visible,
                userLatitude: controller.userLatitude,
                userLongitude: controller.userLongitude,
              ),
            ),
            if (chips.length > 1)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.horizontalPage,
                    vertical: AppSpacing.xs,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        label: const Text('Todos'),
                        selected: controller.selectedSupermarket == null,
                        onSelected: (_) => controller.selectSupermarket(null),
                      ),
                    ),
                    for (final chip in chips)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChoiceChip(
                          label: Text(chip.name),
                          selected: controller.selectedSupermarket == chip.code,
                          onSelected: (_) => controller.selectSupermarket(chip.code),
                        ),
                      ),
                  ],
                ),
              ),
            const _TravelModeBar(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.horizontalPage,
                  AppSpacing.md,
                  AppSpacing.horizontalPage,
                  AppSpacing.xxxl * 2,
                ),
                itemCount: visible.length + (missing.isEmpty ? 0 : 1),
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index == visible.length) {
                    return Text(
                      'Aún no tenemos sedes registradas de ${_joinNames(missing)}. '
                      'Sus precios sí están en la app.',
                      style: AppText.caption,
                    );
                  }
                  final store = visible[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    onTap: () => _showStoreSheet(context, store),
                    child: Container(
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
                                Text(store.supermarketName, style: AppText.productName),
                                Text(
                                  _placeLine(store),
                                  style: AppText.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _distanceLabel(store),
                                style: AppText.priceCard.copyWith(fontSize: 14),
                              ),
                              Text(
                                '${context.watch<PreferencesController>().travelMode.label}: '
                                '~${context.watch<PreferencesController>().travelMode.durationLabel(store.distanceKm)}',
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
    }
  }
}

/// Deja elegir la ubicación a mano (sin GPS), la guarda en Perfil y recarga.
Future<void> _pickManual(BuildContext context, NearbyStoresController controller) async {
  final prefs = context.read<PreferencesController>();
  final picked = await Navigator.of(context).push<ManualLocation>(
    MaterialPageRoute(builder: (_) => PickLocationScreen(initial: prefs.manualLocation)),
  );
  if (picked == null) return;
  // El controlador se entera solo: sigue a las preferencias.
  await prefs.setManualLocation(picked);
}

String _joinNames(List<String> names) {
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
}

/// Dirección o barrio de la sede; si el mapa no los trae, lo dice en vez de
/// repetir el nombre del supermercado.
String _placeLine(NearbyStore store) {
  final parts = [store.address, store.city].whereType<String>().where((p) => p.trim().isNotEmpty);
  return parts.isEmpty ? 'Dirección no disponible' : parts.join(', ');
}

String _distanceLabel(NearbyStore store) => store.distanceKm < 1
    ? '${(store.distanceKm * 1000).round()} m'
    : '${store.distanceKm.toStringAsFixed(1)} km';

Future<void> _openDirections(BuildContext context, NearbyStore store, TravelMode mode) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${store.latitude},${store.longitude}'
    '&travelmode=${mode.googleMode}',
  );
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No pudimos abrir la app de mapas.')),
    );
  }
}

void _showStoreSheet(BuildContext context, NearbyStore store) {
  final prefs = context.read<PreferencesController>();
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final selected = prefs.travelMode;
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(store.supermarketName, style: AppText.screenTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(_placeLine(store), style: AppText.body),
              const SizedBox(height: AppSpacing.xs),
              Text('A ${_distanceLabel(store)} de ti', style: AppText.caption),
              const SizedBox(height: AppSpacing.lg),
              // Tocar un medio lo elige: cambia el tiempo destacado y el botón de abajo.
              Row(
                children: [
                  for (final mode in TravelMode.values)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                        onTap: () {
                          prefs.setTravelMode(mode);
                          setSheetState(() {});
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: mode == selected ? AppColors.lavenderMist : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                            border: Border.all(color: mode == selected ? AppColors.brandIndigo : AppColors.mist),
                          ),
                          child: Column(
                            children: [
                              Icon(mode.icon, color: mode == selected ? AppColors.brandIndigo : AppColors.inkMuted),
                              const SizedBox(height: 2),
                              Text(
                                mode.durationLabel(store.distanceKm),
                                style: AppText.productName.copyWith(
                                  fontSize: 13,
                                  color: mode == selected ? AppColors.brandIndigo : AppColors.ink,
                                ),
                              ),
                              Text(mode.label, style: AppText.caption),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('Tiempos aproximados, sin tráfico. Toca un medio para cambiarlo.', style: AppText.caption),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _openDirections(context, store, prefs.travelMode);
                },
                icon: Icon(selected.icon),
                label: Text('Cómo llegar · ${selected.label}'),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Medio de transporte con el que se calculan los tiempos de llegada.
class _TravelModeBar extends StatelessWidget {
  const _TravelModeBar();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesController>();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage),
        children: [
          for (final mode in TravelMode.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                avatar: Icon(mode.icon, size: 18),
                label: Text(mode.label),
                selected: prefs.travelMode == mode,
                onSelected: (_) => prefs.setTravelMode(mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.lavenderMist,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage, vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brandIndigo),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppText.caption.copyWith(color: AppColors.ink))),
        ],
      ),
    );
  }
}

/// Mapa de OpenStreetMap con un pin por cada establecimiento cercano y otro
/// (distinto) para la posición del usuario. Ningún supermercado tiene un
/// color propio en los pines -- se distinguen por el nombre en el globo de
/// información, igual que en el resto de la app.
class _StoresMap extends StatelessWidget {
  final List<NearbyStore> stores;
  final double? userLatitude;
  final double? userLongitude;

  const _StoresMap({required this.stores, required this.userLatitude, required this.userLongitude});

  @override
  Widget build(BuildContext context) {
    final storePoints = stores
        .where((s) => s.latitude != null && s.longitude != null)
        .map((s) => LatLng(s.latitude!, s.longitude!))
        .toList();

    final userPoint = (userLatitude != null && userLongitude != null)
        ? LatLng(userLatitude!, userLongitude!)
        : null;

    final allPoints = [if (userPoint != null) userPoint, ...storePoints];
    final center = userPoint ?? (storePoints.isNotEmpty ? storePoints.first : const LatLng(0, 0));

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 14,
          initialCameraFit: allPoints.length > 1
              ? CameraFit.coordinates(
                  coordinates: allPoints,
                  padding: const EdgeInsets.all(40),
                )
              : null,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.convenia.convenia_mobile',
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
            ],
          ),
          MarkerLayer(
            markers: [
              if (userPoint != null)
                Marker(
                  point: userPoint,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brandIndigo,
                      border: Border.all(color: AppColors.white, width: 2),
                    ),
                  ),
                ),
              for (final store in stores)
                if (store.latitude != null && store.longitude != null)
                  Marker(
                    point: LatLng(store.latitude!, store.longitude!),
                    // Área táctil pequeña: con una grande los pines cercanos se pisan.
                    width: 34,
                    height: 34,
                    child: GestureDetector(
                      onTap: () => _showStoreSheet(context, store),
                      child: _StorePin(name: store.supermarketName),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<bool> Function() onAction;
  final VoidCallback onRetry;
  final VoidCallback? onPickLocation;

  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onRetry,
    this.onPickLocation,
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
            if (onPickLocation != null) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: onPickLocation, child: const Text('Elegir mi ubicación en el mapa')),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}


/// Pin de una tienda: un círculo con la inicial del supermercado. Más pequeño y
/// legible que un pin negro idéntico para todas las cadenas.
class _StorePin extends StatelessWidget {
  final String name;

  const _StorePin({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.ink,
        border: Border.all(color: AppColors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );
  }
}
