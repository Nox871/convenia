import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/price_history_monthly_response.dart';
import '../models/price_history_response.dart';
import '../repositories/product_repository.dart';
import '../state/price_history_monthly_controller.dart';
import '../state/view_status.dart';
import '../widgets/state_views.dart';

/// Pantalla "Historial" (ERS §15, §23.5) -- resumen mensual con barras
/// verticales (altura ∝ precio promedio del mes) y drill-down al tocar un
/// mes. Responde "¿qué tan normal es el precio actual?": el mes vigente se
/// resalta contra los demás y se anota si está por encima o por debajo del
/// promedio de los meses anteriores. Meses sin observaciones simplemente no
/// aparecen -- nunca se inventan ni se dibujan como $0.
class PriceHistoryScreen extends StatelessWidget {
  final String productId;
  final String productName;

  const PriceHistoryScreen({super.key, required this.productId, required this.productName});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PriceHistoryMonthlyController(productId: productId),
      child: Scaffold(
        appBar: AppBar(title: Text('Historial', style: AppText.screenTitle)),
        body: SafeArea(child: _HistoryBody(productId: productId, productName: productName)),
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  final String productId;
  final String productName;

  const _HistoryBody({required this.productId, required this.productName});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PriceHistoryMonthlyController>();

    switch (controller.status) {
      case ViewStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ViewStatus.error:
        return ErrorResultsView(onRetry: controller.retry);
      case ViewStatus.empty:
        return EmptyResultsView(
          title: 'Sin historial todavía',
          message: 'Aún no tenemos suficientes observaciones de precio para '
              '"$productName".',
          onGoBack: () => Navigator.of(context).maybePop(),
        );
      case ViewStatus.loaded:
        return _MonthlyChart(productId: productId, months: controller.months);
    }
  }
}

class _MonthlyChart extends StatelessWidget {
  final String productId;
  final List<PriceHistoryMonthlyPoint> months;

  const _MonthlyChart({required this.productId, required this.months});

  static const _barMaxHeight = 140.0;
  static const _barWidth = 40.0;

  @override
  Widget build(BuildContext context) {
    final actual = months.last;
    final anteriores = months.length > 1 ? months.sublist(0, months.length - 1) : const <PriceHistoryMonthlyPoint>[];
    final promedioAnterior = anteriores.isEmpty
        ? null
        : anteriores.map((m) => m.avgPrice).reduce((a, b) => a + b) / anteriores.length;
    final maxAvg = months.map((m) => m.avgPrice).reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.horizontalPage,
        AppSpacing.md,
        AppSpacing.horizontalPage,
        AppSpacing.xxxl,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.mist),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Precio promedio de este mes', style: AppText.caption),
              const SizedBox(height: 2),
              Text(formatCop(actual.avgPrice), style: AppText.priceMain),
              if (promedioAnterior != null) ...[
                const SizedBox(height: AppSpacing.xs),
                _ComparisonNote(actual: actual.avgPrice, anterior: promedioAnterior),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Resumen mensual', style: AppText.sectionTitle),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: _barMaxHeight + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            reverse: true, // el mes más reciente queda visible de entrada
            itemCount: months.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final point = months[index];
              final isActual = point.month == actual.month;
              final heightFactor = maxAvg > 0 ? point.avgPrice / maxAvg : 0.0;
              return _MonthBar(
                point: point,
                isActual: isActual,
                heightFactor: heightFactor,
                maxHeight: _barMaxHeight,
                width: _barWidth,
                onTap: () => _openMonthDetail(context, point),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Toca un mes para ver el detalle: mínimo, máximo y cada observación.',
          style: AppText.caption,
        ),
      ],
    );
  }

  void _openMonthDetail(BuildContext context, PriceHistoryMonthlyPoint point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MonthDetailSheet(productId: productId, point: point),
    );
  }
}

class _ComparisonNote extends StatelessWidget {
  final double actual;
  final double anterior;

  const _ComparisonNote({required this.actual, required this.anterior});

  @override
  Widget build(BuildContext context) {
    final diferencia = ((actual - anterior) / anterior) * 100;
    final subiendo = diferencia > 1;
    final bajando = diferencia < -1;
    final color = subiendo ? AppColors.error : (bajando ? AppColors.success : AppColors.inkMuted);
    final texto = subiendo
        ? 'Está ${diferencia.abs().toStringAsFixed(0)}% por encima del promedio de meses anteriores'
        : bajando
            ? 'Está ${diferencia.abs().toStringAsFixed(0)}% por debajo del promedio de meses anteriores'
            : 'Está en línea con el promedio de meses anteriores';

    return Row(
      children: [
        Icon(
          subiendo
              ? Icons.arrow_upward_rounded
              : (bajando ? Icons.arrow_downward_rounded : Icons.remove_rounded),
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(texto, style: AppText.caption.copyWith(color: color))),
      ],
    );
  }
}

class _MonthBar extends StatelessWidget {
  final PriceHistoryMonthlyPoint point;
  final bool isActual;
  final double heightFactor;
  final double maxHeight;
  final double width;
  final VoidCallback onTap;

  const _MonthBar({
    required this.point,
    required this.isActual,
    required this.heightFactor,
    required this.maxHeight,
    required this.width,
    required this.onTap,
  });

  String get _monthLabel {
    const nombres = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    final partes = point.month.split('-');
    final mesIndex = int.parse(partes[1]) - 1;
    return nombres[mesIndex];
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = (maxHeight * heightFactor).clamp(8.0, maxHeight);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: maxHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: width * 0.6,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: isActual ? AppColors.brandIndigo : AppColors.lavenderMist,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _monthLabel,
              style: AppText.caption.copyWith(
                color: isActual ? AppColors.ink : AppColors.inkFaint,
                fontWeight: isActual ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthDetailSheet extends StatefulWidget {
  final String productId;
  final PriceHistoryMonthlyPoint point;

  const _MonthDetailSheet({required this.productId, required this.point});

  @override
  State<_MonthDetailSheet> createState() => _MonthDetailSheetState();
}

class _MonthDetailSheetState extends State<_MonthDetailSheet> {
  final _repository = ProductRepository();
  List<PriceHistoryPoint>? _observations;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _repository.getPriceHistory(
        widget.productId,
        month: widget.point.month,
        limit: 100,
      );
      if (mounted) setState(() => _observations = result.observations);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos cargar las observaciones de este mes.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(_fullMonthLabel(point.month), style: AppText.sectionTitle),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  _StatColumn(label: 'Mínimo', value: formatCop(point.minPrice)),
                  _StatColumn(label: 'Promedio', value: formatCop(point.avgPrice)),
                  _StatColumn(label: 'Máximo', value: formatCop(point.maxPrice)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('${point.observationsCount} observaciones', style: AppText.caption),
              const Divider(height: AppSpacing.xxl),
              if (_loading)
                const Center(child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: CircularProgressIndicator(),
                ))
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.error))
              else
                ..._observations!.map((obs) => _ObservationRow(observation: obs)),
            ],
          ),
        );
      },
    );
  }

  String _fullMonthLabel(String month) {
    const nombres = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto',
      'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    final partes = month.split('-');
    final mesIndex = int.parse(partes[1]) - 1;
    return '${nombres[mesIndex]} ${partes[0]}';
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(height: 2),
          Text(value, style: AppText.productName),
        ],
      ),
    );
  }
}

class _ObservationRow extends StatelessWidget {
  final PriceHistoryPoint observation;

  const _ObservationRow({required this.observation});

  @override
  Widget build(BuildContext context) {
    final local = observation.observedAt.toLocal();
    final fecha =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fecha, style: AppText.body),
                if (!observation.available)
                  const Text(
                    'No disponible en ese momento',
                    style: TextStyle(fontSize: 11, color: AppColors.error),
                  ),
              ],
            ),
          ),
          Text(formatCop(observation.price), style: AppText.priceCard),
        ],
      ),
    );
  }
}
