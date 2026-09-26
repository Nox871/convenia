import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/coverage.dart';
import '../repositories/store_repository.dart';
import 'preferences_controller.dart';
import '../services/api_client.dart';

enum CoverageStatus { unknown, ready, unavailable }

/// Por qué no se pudo filtrar por cercanía.
enum CoverageProblem { gpsOff, permission, failed }

/// Qué supermercados están al alcance de la persona: los que tienen al menos
/// una tienda dentro de su distancia máxima. Los precios de los demás no se
/// muestran, porque no habría dónde comprar.
///
/// Se resuelve de forma perezosa (la primera consulta de precios lo pide) y
/// se guarda en memoria unos minutos. Si no hay ubicación, no se filtra nada
/// y se avisa: es preferible mostrar todo con una nota que esconder precios
/// sin poder justificarlo.
class CoverageController extends ChangeNotifier {
  static const _freshFor = Duration(minutes: 10);
  static const _retryUnavailableAfter = Duration(minutes: 1);

  final StoreRepository _repository;

  CoverageController({StoreRepository? repository})
    : _repository = repository ?? StoreRepository() {
    ApiClient.scopeResolver = resolveScope;
  }

  double radiusKm = 5.0;
  CoverageStatus status = CoverageStatus.unknown;
  CoverageProblem? problem;
  List<SupermarketCoverage> supermarkets = [];

  /// Ubicación elegida a mano; si existe, manda sobre el GPS.
  ManualLocation? manualLocation;

  double? _latitude;
  double? _longitude;
  DateTime? _loadedAt;
  Future<List<String>?>? _pending;
  bool _askedPermission = false;

  /// Códigos al alcance, o `null` si no se puede filtrar.
  List<String>? get scope => status == CoverageStatus.ready
      ? [for (final s in supermarkets) if (s.inRange) s.code]
      : null;

  List<SupermarketCoverage> get inRange => [for (final s in supermarkets) if (s.inRange) s];
  List<SupermarketCoverage> get outOfRange => [for (final s in supermarkets) if (!s.inRange) s];

  bool get _isFresh {
    final at = _loadedAt;
    if (at == null) return false;
    final ttl = status == CoverageStatus.ready ? _freshFor : _retryUnavailableAfter;
    return DateTime.now().difference(at) < ttl;
  }

  Future<List<String>?> resolveScope() {
    if (_isFresh) return Future.value(scope);
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  /// Sigue a las preferencias de la persona (distancia y ubicación elegida).
  ///
  /// Con `eager: false` (lo que hace el arranque de la app) no consulta la red
  /// todavía: la cobertura se calcula cuando una consulta de precios la pide.
  Future<void> configure({
    required double radiusKm,
    required ManualLocation? manual,
    bool eager = true,
  }) async {
    if (manual != manualLocation) {
      manualLocation = manual;
      this.radiusKm = radiusKm;
      _loadedAt = null;
      _latitude = null;
      _longitude = null;
      _askedPermission = false;
      if (manual != null && eager) {
        _latitude = manual.latitude;
        _longitude = manual.longitude;
        try {
          await _fetchCoverage();
        } catch (_) {
          _unavailable(CoverageProblem.failed);
          return;
        }
      } else {
        status = CoverageStatus.unknown;
        problem = null;
        supermarkets = [];
      }
      // Puede llegar durante la construcción de un widget: se notifica después.
      scheduleMicrotask(notifyListeners);
      return;
    }
    await setRadius(radiusKm);
  }

  /// Cambia la distancia máxima; reutiliza la última posición conocida.
  Future<void> setRadius(double km) async {
    if (km == radiusKm) return;
    radiusKm = km;
    if (_latitude != null && _longitude != null) {
      await _fetchCoverage();
      notifyListeners();
    } else {
      _loadedAt = null;
    }
  }

  /// Reintenta (por ejemplo, tras activar la ubicación); puede mostrar el
  /// diálogo de permisos del sistema.
  Future<void> refresh() async {
    _loadedAt = null;
    _askedPermission = false;
    await (_pending ??= _load(askPermission: true).whenComplete(() => _pending = null));
  }

  Future<List<String>?> _load({bool askPermission = false}) async {
    try {
      final manual = manualLocation;
      if (manual != null) {
        _latitude = manual.latitude;
        _longitude = manual.longitude;
        await _fetchCoverage();
        notifyListeners();
        return scope;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _unavailable(CoverageProblem.gpsOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && (askPermission || !_askedPermission)) {
        _askedPermission = true;
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return _unavailable(CoverageProblem.permission);
      }

      final position = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 6),
            ),
          ).timeout(const Duration(seconds: 8));
      _latitude = position.latitude;
      _longitude = position.longitude;
      await _fetchCoverage();
      notifyListeners();
      return scope;
    } catch (e) {
      debugPrint('CoverageController: no se pudo determinar la cobertura: $e');
      return _unavailable(CoverageProblem.failed);
    }
  }

  Future<void> _fetchCoverage() async {
    supermarkets = await _repository.getCoverage(
      latitude: _latitude!,
      longitude: _longitude!,
      radiusKm: radiusKm,
    );
    status = CoverageStatus.ready;
    problem = null;
    _loadedAt = DateTime.now();
  }

  List<String>? _unavailable(CoverageProblem reason) {
    status = CoverageStatus.unavailable;
    problem = reason;
    supermarkets = [];
    _loadedAt = DateTime.now();
    notifyListeners();
    return null;
  }
}
