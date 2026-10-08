import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/travel_mode.dart';

/// Ubicación que la persona eligió a mano (por ejemplo, porque no da
/// permiso de GPS). Se guarda sólo en este teléfono.
class ManualLocation {
  final double latitude;
  final double longitude;
  final String label;

  const ManualLocation({required this.latitude, required this.longitude, required this.label});

  @override
  bool operator ==(Object other) =>
      other is ManualLocation && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Con qué criterio se propone el producto cuando se arma una lista con
/// palabras cotidianas ("leche", "arroz").
enum SuggestionPreference {
  /// El que más supermercados venden: permite comparar de verdad.
  comparable('comparable', 'Más comparables', 'Productos que se venden en más supermercados'),

  /// El de menor precio entre los que coinciden con lo pedido.
  cheapest('price', 'Más baratos', 'El de menor precio que coincide con lo que pides');

  final String apiValue;
  final String label;
  final String description;

  const SuggestionPreference(this.apiValue, this.label, this.description);
}

/// Preferencias de la persona en este teléfono. Se guardan localmente; si el
/// almacenamiento falla, se usa el valor por defecto sin interrumpir la app.
class PreferencesController extends ChangeNotifier {
  static const _key = 'suggestion_preference';
  static const _distanceKey = 'max_distance_km';
  static const _latKey = 'manual_latitude';
  static const _lonKey = 'manual_longitude';
  static const _labelKey = 'manual_location_label';
  static const _travelKey = 'travel_mode';

  /// Distancias entre las que puede elegir la persona (km).
  static const distanceOptionsKm = [1.0, 2.0, 5.0, 10.0, 20.0];

  /// Hasta dónde está dispuesta a ir a comprar. Sólo se comparan los
  /// supermercados con una tienda dentro de esta distancia.
  double maxDistanceKm = 5.0;

  SuggestionPreference suggestion = SuggestionPreference.comparable;

  /// Cómo suele ir a las tiendas (para los tiempos de llegada).
  TravelMode travelMode = TravelMode.walking;

  /// Si está definida, se usa en lugar del GPS.
  ManualLocation? manualLocation;

  PreferencesController() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      final savedDistance = prefs.getDouble(_distanceKey);
      travelMode = TravelMode.fromName(prefs.getString(_travelKey));
      final lat = prefs.getDouble(_latKey);
      final lon = prefs.getDouble(_lonKey);
      if (lat != null && lon != null) {
        manualLocation = ManualLocation(
          latitude: lat,
          longitude: lon,
          label: prefs.getString(_labelKey) ?? 'Ubicación elegida',
        );
      }
      if (savedDistance != null && distanceOptionsKm.contains(savedDistance)) {
        maxDistanceKm = savedDistance;
      }
      for (final option in SuggestionPreference.values) {
        if (option.apiValue == saved) suggestion = option;
      }
      notifyListeners();
    } catch (_) {
      // Sin almacenamiento se queda el valor por defecto.
    }
  }

  Future<void> setSuggestion(SuggestionPreference value) async {
    suggestion = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.apiValue);
    } catch (_) {}
  }

  Future<void> setTravelMode(TravelMode mode) async {
    if (mode == travelMode) return;
    travelMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_travelKey, mode.name);
    } catch (_) {}
  }

  Future<void> setMaxDistanceKm(double km) async {
    if (km == maxDistanceKm) return;
    maxDistanceKm = km;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_distanceKey, km);
    } catch (_) {}
  }

  /// Fija la ubicación elegida a mano, o vuelve al GPS con `null`.
  Future<void> setManualLocation(ManualLocation? location) async {
    manualLocation = location;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (location == null) {
        await prefs.remove(_latKey);
        await prefs.remove(_lonKey);
        await prefs.remove(_labelKey);
      } else {
        await prefs.setDouble(_latKey, location.latitude);
        await prefs.setDouble(_lonKey, location.longitude);
        await prefs.setString(_labelKey, location.label);
      }
    } catch (_) {}
  }
}
