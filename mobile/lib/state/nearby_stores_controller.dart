import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api_exception.dart';
import '../models/physical_store.dart';
import '../repositories/store_repository.dart';

enum NearbyStoresStatus {
  loading,
  loaded,
  empty,
  error,
  permissionDenied,
  locationDisabled,
  timedOut,
}

/// Estado de la pantalla "Establecimientos" (ERS §17, RF-STORE-001/002).
///
/// La ubicación es SIEMPRE opcional: si el usuario no concede el permiso, o
/// el dispositivo tiene el GPS apagado, la app no se rompe -- sólo informa
/// la situación y deja reintentar; nunca bloquea el resto de la app.
class NearbyStoresController extends ChangeNotifier {
  final StoreRepository _repository;

  NearbyStoresController({StoreRepository? repository})
    : _repository = repository ?? StoreRepository() {
    _load();
  }

  NearbyStoresStatus status = NearbyStoresStatus.loading;
  String? errorMessage;
  List<NearbyStore> stores = [];

  Future<void> retry() => _load();

  Future<void> _load() async {
    status = NearbyStoresStatus.loading;
    notifyListeners();

    if (!await Geolocator.isLocationServiceEnabled()) {
      status = NearbyStoresStatus.locationDisabled;
      notifyListeners();
      return;
    }

    var permission = await Geolocator.checkPermission();
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
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(const Duration(seconds: 12));

      final result = await _repository.listStoresNearby(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      stores = result;
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
}
