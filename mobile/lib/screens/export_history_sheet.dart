import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../models/supermarket.dart';
import '../repositories/admin_repository.dart';
import '../repositories/supermarket_repository.dart';

/// Hoja para exportar el historial de precios a CSV (sólo administradores):
/// se elige supermercado y periodo, se descarga y se abre el menú de compartir
/// del teléfono para guardarlo o enviarlo.
class ExportHistorySheet extends StatefulWidget {
  const ExportHistorySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const ExportHistorySheet(),
  );

  @override
  State<ExportHistorySheet> createState() => _ExportHistorySheetState();
}

class _ExportHistorySheetState extends State<ExportHistorySheet> {
  static const _periods = [7, 30, 90];

  final _admin = AdminRepository();
  List<Supermarket> _supermarkets = [];
  String? _supermarket;
  int _days = 30;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SupermarketRepository().listSupermarkets().then((items) {
      if (mounted) setState(() => _supermarkets = items.where((s) => s.isActive).toList());
    }).catchError((_) {});
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await _admin.downloadPriceHistoryCsv(supermarket: _supermarket, days: _days);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path, mimeType: 'text/csv')], text: 'Historial de precios de Convenia'),
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos generar el archivo. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Exportar historial de precios', style: AppText.screenTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Genera un archivo CSV con una fila por cada precio registrado. Se abre con Excel '
            'o Google Sheets.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Supermercado', style: AppText.caption),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: _supermarket == null,
                onSelected: _busy ? null : (_) => setState(() => _supermarket = null),
              ),
              for (final s in _supermarkets)
                ChoiceChip(
                  label: Text(s.name),
                  selected: _supermarket == s.code,
                  onSelected: _busy ? null : (_) => setState(() => _supermarket = s.code),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Periodo', style: AppText.caption),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final days in _periods)
                ChoiceChip(
                  label: Text('Últimos $days días'),
                  selected: _days == days,
                  onSelected: _busy ? null : (_) => setState(() => _days = days),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: AppText.body.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            label: Text(_busy ? 'Generando…' : 'Exportar y compartir'),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
          ),
        ],
      ),
    );
  }
}
