import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api_exception.dart';
import '../models/physical_store.dart';
import '../models/supermarket.dart';
import 'preferences_controller.dart';
import '../repositories/store_repository.dart';
import '../repositories/supermarket_repository.dart';

enum NearbyStoresStatus {
  loading,
  loaded,
  empty,
  error,
  permissionDenied,
  locationDisabled,
  timedOut,
}

/// Estado de la pantalla "Establecimientos".
///
/// La ubicación es SIEMPRE opcional: si el usuario no concede el permiso, o
/// el dispositivo tiene el GPS apagado, la app no se rompe -- sólo informa
/// la situación y deja reintentar; nunca bloquea el resto de la app.
class NearbyStoresController extends ChangeNotifier {
  /// Radios de búsqueda que se prueban en orden hasta encontrar tiendas: no
  /// estar a 5 km de una tienda no significa que no existan, solo que están
  /// más lejos, y decir "no hay tiendas" sería falso.
  /// Radio que se considera "cerca": la distancia máxima que eligió la
  /// persona en Perfil. Si no hay nada ahí, se amplía a 30 y a 100 km.
  double nearRadiusKm;

  /// Ubicación elegida a mano: si existe, no se usa el GPS.
  ManualLocation? manualLocation;

  /// Sigue a las preferencias de Perfil: si cambió la distancia o la ubicación
  /// elegida (o se volvió al GPS), vuelve a buscar. La pestaña de Tiendas se
  /// crea una sola vez, por eso necesita enterarse.
  void configure({required double nearRadiusKm, required ManualLocation? manual}) {
    if (nearRadiusKm == this.nearRadiusKm && manual == manualLocation) return;
    this.nearRadiusKm = nearRadiusKm;
    manualLocation = manual;
    // Puede llegar durante la construcción de un widget.
    scheduleMicrotask(_load);
  }

  List<double> get _radiiKm => [nearRadiusKm, if (nearRadiusKm < 30) 30.0, 100.0];

  final StoreRepository _repository;
  final SupermarketRepository _supermarketRepository;

  NearbyStoresController({
    this.nearRadiusKm = 5.0,
    this.manualLocation,
    StoreRepository? repository,
    SupermarketRepository? supermarketRepository,
  }) : _repository = repository ?? StoreRepository(),
      _supermarketRepository = supermarketRepository ?? SupermarketRepository() {
    _load();
  }

  NearbyStoresStatus status = NearbyStoresStatus.loading;
  String? errorMessage;
  List<NearbyStore> stores = [];
  double? userLatitude;
  double? userLongitude;

  /// Radio con el que se encontraron las tiendas mostradas.
  late double searchRadiusKm = nearRadiusKm;

  /// Supermercados de Convenia que todavía no tienen ninguna sede
  /// registrada en ningún lado (ej. no están en OpenStreetMap).
  List<String> supermarketsWithoutStores = [];

  /// Código de supermercado elegido en el filtro, o `null` para todos.
  String? selectedSupermarket;

  bool get radiusWasExpanded => searchRadiusKm > nearRadiusKm;

  /// Supermercados presentes en las tiendas encontradas, para los filtros.
  List<({String code, String name})> get availableSupermarkets {
    final seen = <String, String>{};
    for (final s in stores) {
      seen.putIfAbsent(s.supermarketCode, () => s.supermarketName);
    }
    return [for (final e in seen.entries) (code: e.key, name: e.value)];
  }

  List<NearbyStore> get visibleStores => selectedSupermarket == null
      ? stores
      : stores.where((s) => s.supermarketCode == selectedSupermarket).toList();

  void selectSupermarket(String? code) {
    selectedSupermarket = code;
    notifyListeners();
  }

  Future<void> retry() => _load();

  Future<void> _load() async {
    status = NearbyStoresStatus.loading;
    notifyListeners();

    final manual = manualLocation;
    if (manual == null && !await Geolocator.isLocationServiceEnabled()) {
      status = NearbyStoresStatus.locationDisabled;
      notifyListeners();
      return;
    }

    var permission = manual != null ? LocationPermission.whileInUse : await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      status = NearbyStoresStatus.permissionDenied;
      notifyListeners();
      return;
    }

    try {
      // IMPORTANTE: sin `timeLimit`, en un emulador o interior sin fix de GPS
      // rápido este `await` puede colgar indefinidamente y la pantalla queda
      // en "loading" para siempre (parece que "no muestra nada" en vez de
      // fallar). El `.timeout(...)` exterior es una segunda red de
      // seguridad por si el propio plugin no respeta `timeLimit` en alguna
      // plataforma.
      final position = manual != null
          ? (latitude: manual.latitude, longitude: manual.longitude)
          : await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 10),
              ),
            ).timeout(const Duration(seconds: 12)).then((p) => (latitude: p.latitude, longitude: p.longitude));

      userLatitude = position.latitude;
      userLongitude = position.longitude;

      var result = <NearbyStore>[];
      for (final radius in _radiiKm) {
        result = await _repository.listStoresNearby(
          latitude: position.latitude,
          longitude: position.longitude,
          radiusKm: radius,
        );
        searchRadiusKm = radius;
        if (result.isNotEmpty) break;
      }
      stores = result;
      selectedSupermarket = null;
      await _loadSupermarketsWithoutStores();
      status = result.isEmpty ? NearbyStoresStatus.empty : NearbyStoresStatus.loaded;
    } on TimeoutException {
      status = NearbyStoresStatus.timedOut;
    } on ApiException catch (e) {
      status = NearbyStoresStatus.error;
      errorMessage = e.message;
    } catch (e) {
      // No se silencia del todo: queda en consola para poder diagnosticar
      // casos reales de plataforma (antes este catch-all no dejaba rastro).
      debugPrint('NearbyStoresController: error obteniendo ubicación: $e');
      status = NearbyStoresStatus.error;
      errorMessage = 'No pudimos obtener tu ubicación.';
    }

    notifyListeners();
  }

  /// Es informativo: si falla, simplemente no se muestra el aviso.
  Future<void> _loadSupermarketsWithoutStores() async {
    try {
      final results = await Future.wait([
        _supermarketRepository.listSupermarkets(),
        _repository.listStores(),
      ]);
      final supermarkets = results[0] as List<Supermarket>;
      final withStores = (results[1] as List<PhysicalStore>).map((s) => s.supermarketCode).toSet();
      supermarketsWithoutStores = [
        for (final s in supermarkets)
          if (s.isActive && !withStores.contains(s.code)) s.name,
      ];
    } catch (_) {
      supermarketsWithoutStores = [];
    }
  }
}
