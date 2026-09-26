import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../models/supermarket.dart';
import '../repositories/store_repository.dart';
import '../repositories/supermarket_repository.dart';

/// Alta manual de un establecimiento -- sólo visible para administradores
/// (ver `AuthController.isAdmin`). Existe porque el scraper de
/// OpenStreetMap no cubre todas las tiendas reales (ej. una D1 nueva que
/// un usuario reporta que existe pero el mapa todavía no tiene) -- dejar
/// que cualquier usuario agregara tiendas permitiría inventar ubicaciones
/// falsas, así que sólo un admin puede hacerlo, y siempre tocando el punto
/// real en el mapa (nunca escribiendo coordenadas a mano, que es fácil de
/// equivocar).
class AddStoreScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const AddStoreScreen({super.key, this.initialLatitude, this.initialLongitude});

  @override
  State<AddStoreScreen> createState() => _AddStoreScreenState();
}

class _AddStoreScreenState extends State<AddStoreScreen> {
  final _storeRepository = StoreRepository();
  final _supermarketRepository = SupermarketRepository();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();

  List<Supermarket>? _supermarkets;
  Supermarket? _selectedSupermarket;
  LatLng? _selectedPoint;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPoint = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
    _supermarketRepository.listSupermarkets().then((items) {
      if (mounted) setState(() => _supermarkets = items);
    }).catchError((_) {
      if (mounted) setState(() => _supermarkets = []);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final point = _selectedPoint;
    final supermarket = _selectedSupermarket;
    if (point == null || supermarket == null || _nameController.text.trim().isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _storeRepository.createStore(
        supermarketCode: supermarket.code,
        name: _nameController.text.trim(),
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _selectedPoint != null &&
        _selectedSupermarket != null &&
        _nameController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text('Agregar establecimiento', style: AppText.screenTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.horizontalPage),
              child: Text(
                'Toca en el mapa el punto exacto donde está la tienda.',
                style: AppText.caption,
              ),
            ),
            SizedBox(
              height: 260,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _selectedPoint ?? const LatLng(7.1193, -73.1227),
                  initialZoom: 14,
                  onTap: (tapPosition, point) => setState(() => _selectedPoint = point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.convenia.convenia_mobile',
                  ),
                  const RichAttributionWidget(
                    attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                  ),
                  if (_selectedPoint != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedPoint!,
                          width: 40,
                          height: 40,
                          alignment: Alignment.bottomCenter,
                          child: const Icon(Icons.location_on_rounded, color: AppColors.brandIndigo, size: 40),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.horizontalPage),
                children: [
                  if (_supermarkets == null)
                    const Center(child: CircularProgressIndicator())
                  else
                    DropdownButtonFormField<Supermarket>(
                      initialValue: _selectedSupermarket,
                      decoration: const InputDecoration(labelText: 'Supermercado'),
                      items: _supermarkets!
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                          .toList(),
                      onChanged: (value) => setState(() => _selectedSupermarket = value),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nombre del punto de venta'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(labelText: 'Dirección (opcional)'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: 'Ciudad (opcional)'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(
                    onPressed: canSubmit && !_submitting ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar establecimiento'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
