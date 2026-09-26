import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/supermarket.dart';
import '../state/settings_controller.dart';
import '../state/view_status.dart';
import '../widgets/state_views.dart';

/// Fuente de los datos y fecha de la última actualización de cada
/// supermercado -- nunca se presenta un dato desactualizado como si fuera
/// actual sin decir cuándo se observó. Vive en su propia pantalla porque es
/// información de referencia, no algo que el usuario consulte a diario.
class DataSourceScreen extends StatelessWidget {
  const DataSourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsController(),
      child: Scaffold(
        appBar: AppBar(title: Text('Fuente de datos', style: AppText.screenTitle)),
        body: const SafeArea(child: _DataSourceBody()),
      ),
    );
  }
}

class _DataSourceBody extends StatelessWidget {
  const _DataSourceBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.horizontalPage),
      children: [
        Text(
          'Convenia obtiene precios directamente de los sitios públicos de cada '
          'supermercado mediante procesos automatizados. Cada precio mostrado '
          'indica cuándo fue observado por última vez.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('ÚLTIMA ACTUALIZACIÓN POR SUPERMERCADO', style: AppText.caption),
        const SizedBox(height: AppSpacing.sm),
        _buildSupermarketsList(controller),
      ],
    );
  }

  Widget _buildSupermarketsList(SettingsController controller) {
    switch (controller.status) {
      case ViewStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: LinearProgressIndicator(),
        );
      case ViewStatus.error:
        return ErrorResultsView(onRetry: controller.retry);
      case ViewStatus.empty:
        return Text('Sin supermercados configurados.', style: AppText.body);
      case ViewStatus.loaded:
        return Column(
          children: controller.supermarkets.map(_SupermarketRow.new).toList(),
        );
    }
  }
}

class _SupermarketRow extends StatelessWidget {
  final Supermarket supermarket;

  const _SupermarketRow(this.supermarket);

  String _formatDate(DateTime? date) {
    if (date == null) return 'Sin datos todavía';
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(supermarket.name, style: AppText.productName)),
          Text(_formatDate(supermarket.lastSuccessfulRunAt), style: AppText.caption),
        ],
      ),
    );
  }
}
