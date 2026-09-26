import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import '../state/preferences_controller.dart';

/// Atajos a las ciudades del área metropolitana; el punto exacto se ajusta
/// moviendo el mapa.
const _presetCities = <(String, LatLng)>[
  ('Bucaramanga', LatLng(7.1193, -73.1227)),
  ('Floridablanca', LatLng(7.0622, -73.0864)),
  ('Girón', LatLng(7.0682, -73.1698)),
  ('Piedecuesta', LatLng(6.9877, -73.0498)),
];

/// Permite elegir a mano dónde está la persona (o desde dónde quiere
/// comprar) cuando no hay GPS o prefiere no darlo.
///
/// El pin queda fijo en el centro y se MUEVE EL MAPA debajo de él: es más
/// exacto que tocar y permite acercar el mapa hasta la cuadra. Devuelve una
/// [ManualLocation] con `Navigator.pop`.
class PickLocationScreen extends StatefulWidget {
  final ManualLocation? initial;

  const PickLocationScreen({super.key, this.initial});

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  static const _movedLabel = 'Punto elegido en el mapa';

  final _map = MapController();
  late LatLng _center;
  late String _label;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _center = initial == null
        ? _presetCities.first.$2
        : LatLng(initial.latitude, initial.longitude);
    _label = initial?.label ?? _presetCities.first.$1;
  }

  void _goTo(String name, LatLng point) {
    _label = name;
    _map.move(point, 14);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Elegir mi ubicación', style: AppText.screenTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.horizontalPage,
                AppSpacing.md,
                AppSpacing.horizontalPage,
                AppSpacing.sm,
              ),
              child: Text(
                'Mueve el mapa hasta que el pin quede sobre tu ubicación. '
                'Acércalo con dos dedos para más precisión.',
                style: AppText.body,
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage),
                children: [
                  for (final city in _presetCities)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ActionChip(
                        label: Text(city.$1),
                        onPressed: () => _goTo(city.$1, city.$2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: widget.initial == null ? 13 : 15,
                      minZoom: 9,
                      onPositionChanged: (camera, hasGesture) {
                        _center = camera.center;
                        // Si la persona movió el mapa, ya no es "la ciudad" del atajo.
                        if (hasGesture) _label = _movedLabel;
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.convenia.convenia_mobile',
                      ),
                      const RichAttributionWidget(
                        attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                      ),
                    ],
                  ),
                  // La punta del pin queda justo en el centro del mapa.
                  const IgnorePointer(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 44),
                      child: Icon(Icons.location_on_rounded, size: 44, color: AppColors.brandIndigo),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.horizontalPage),
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(
                  ManualLocation(
                    latitude: _center.latitude,
                    longitude: _center.longitude,
                    label: _label,
                  ),
                ),
                child: const Text('Usar esta ubicación'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
