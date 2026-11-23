import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api_exception.dart';
import '../core/barcode.dart';
import '../core/theme.dart';
import '../models/compare_response.dart';
import '../repositories/product_repository.dart';
import '../widgets/add_to_list_sheet.dart';
import '../widgets/ar_comparison_card.dart';

enum _ArStatus { scanning, loading, result, notFound, invalid, error }

/// Convenia AR: se apunta la cámara al código de barras de un producto y la
/// comparación de precios aparece sobre la imagen. El código se lee en el
/// teléfono; solo el número viaja a la API (no se guardan ni envían imágenes).
class ArScanScreen extends StatefulWidget {
  final ProductRepository? repository;

  const ArScanScreen({super.key, this.repository});

  @override
  State<ArScanScreen> createState() => _ArScanScreenState();
}

class _ArScanScreenState extends State<ArScanScreen> {
  late final ProductRepository _repository =
      widget.repository ?? ProductRepository();
  final _scanner = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  _ArStatus _status = _ArStatus.scanning;
  CompareResponse? _data;
  String? _lastCode;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_status != _ArStatus.scanning) return;
    for (final b in capture.barcodes) {
      final code = cleanBarcode(b.rawValue);
      if (code != null) {
        _lookup(code);
        return;
      }
    }
  }

  Future<void> _lookup(String code) async {
    setState(() {
      _status = _ArStatus.loading;
      _lastCode = code;
    });
    try {
      final data = await _repository.compareByEan(code);
      if (!mounted) return;
      setState(() {
        _data = data;
        _status = _ArStatus.result;
      });
    } on NotFoundException {
      if (mounted) setState(() => _status = _ArStatus.notFound);
    } on ApiException catch (e) {
      // La API responde 400 con «no es un código de barras válido» cuando falla el dígito verificador.
      final invalid = e.message.contains('código de barras');
      if (mounted) setState(() => _status = invalid ? _ArStatus.invalid : _ArStatus.error);
    } catch (_) {
      if (mounted) setState(() => _status = _ArStatus.error);
    }
  }

  void _scanAgain() {
    setState(() {
      _status = _ArStatus.scanning;
      _data = null;
    });
  }

  Future<void> _typeCode() async {
    final controller = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Escribir el código'),
        content: TextField(
          key: const Key('ar_code_field'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Ej. 7702025151585'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Consultar')),
        ],
      ),
    );
    if (typed == null || !mounted) return;
    final code = cleanBarcode(typed);
    if (code == null) {
      setState(() => _status = _ArStatus.invalid);
    } else {
      _lookup(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _CameraUnavailable(onType: _typeCode),
          ),
          const _Reticle(),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Volver',
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text('Convenia AR',
                        style: AppText.screenTitle
                            .copyWith(color: Colors.white, fontSize: 18)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Linterna',
                      icon: const Icon(Icons.flashlight_on_outlined,
                          color: Colors.white),
                      onPressed: () => _scanner.toggleTorch(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(12), child: _bottomPanel()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomPanel() {
    switch (_status) {
      case _ArStatus.scanning:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xD11B2433),
                  borderRadius: BorderRadius.circular(16)),
              child: const Text('Apunta al código de barras del producto',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              key: const Key('ar_type'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _typeCode,
              icon: const Icon(Icons.keyboard_rounded),
              label: const Text('Escribir el código'),
            ),
          ],
        );
      case _ArStatus.loading:
        return _MessageCard(
          icon: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          text: 'Consultando precios del código ${_lastCode ?? ''}…',
        );
      case _ArStatus.result:
        return ArComparisonCard(
          data: _data!,
          onAdd: () => showAddToListSheet(context, _data!.product.id),
          onClose: _scanAgain,
        );
      case _ArStatus.notFound:
        return _MessageCard(
          icon: const Icon(Icons.search_off_rounded, color: AppColors.warning),
          text:
              'No encontré el código ${_lastCode ?? ''} en la base de Convenia. Prueba con otro producto o búscalo por nombre.',
          action: TextButton(
              onPressed: _scanAgain, child: const Text('Intentar de nuevo')),
        );
      case _ArStatus.invalid:
        return _MessageCard(
          icon: const Icon(Icons.error_outline_rounded, color: AppColors.error),
          text: 'Ese código no es válido. Revisa que estén todos los dígitos del código de barras.',
          action: TextButton(
              onPressed: _scanAgain, child: const Text('Intentar de nuevo')),
        );
      case _ArStatus.error:
        return _MessageCard(
          icon: const Icon(Icons.wifi_off_rounded, color: AppColors.error),
          text:
              'No pude consultar los precios. Revisa la conexión e intenta de nuevo.',
          action: TextButton(
              onPressed: () => _lookup(_lastCode ?? ''),
              child: const Text('Reintentar')),
        );
    }
  }
}

class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 280,
          height: 170,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF7FE0B0), width: 3),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final Widget icon;
  final String text;
  final Widget? action;

  const _MessageCard({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius)),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: AppText.body.copyWith(color: AppColors.ink))),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  final VoidCallback onType;

  const _CameraUnavailable({required this.onType});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF17171C),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined,
              color: Colors.white70, size: 40),
          const SizedBox(height: 12),
          const Text(
            'No pude usar la cámara. Revisa el permiso en Ajustes o escribe el código a mano.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: onType, child: const Text('Escribir el código')),
        ],
      ),
    );
  }
}
