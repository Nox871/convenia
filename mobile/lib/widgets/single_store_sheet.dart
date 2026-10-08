import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/single_store.dart';
import '../state/shopping_list_detail_controller.dart';
import 'product_image.dart';

/// Resultado de aplicar una opción: lo que el detalle de la lista muestra como cierre.
typedef SingleStoreDone = ({String store, int replaced, double? total});

/// "Comprar todo en un solo lugar": si ningún supermercado tiene toda la lista, se
/// proponen reemplazos parecidos DENTRO de un mismo supermercado para que la persona
/// vaya a uno solo. Devuelve el resultado si se aplicó algo, o null.
Future<SingleStoreDone?> showSingleStoreSheet(
  BuildContext context,
  ShoppingListDetailController controller,
) {
  return showModalBottomSheet<SingleStoreDone>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => SingleStoreSheet(controller: controller),
  );
}

class SingleStoreSheet extends StatefulWidget {
  final ShoppingListDetailController controller;

  const SingleStoreSheet({super.key, required this.controller});

  @override
  State<SingleStoreSheet> createState() => _SingleStoreSheetState();
}

class _SingleStoreSheetState extends State<SingleStoreSheet> {
  List<SingleStoreOption>? _options;
  SingleStoreOption? _selected;
  bool _failed = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _options = null;
    });
    try {
      final options = await widget.controller.loadSingleStoreOptions();
      if (mounted) setState(() => _options = options);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _apply(SingleStoreOption option) async {
    setState(() => _applying = true);
    final done = await widget.controller.applySingleStoreOption(option);
    if (!mounted) return;
    if (done == 0) {
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos hacer los cambios. Intenta de nuevo.')),
      );
      return;
    }
    Navigator.of(context).pop<SingleStoreDone>(
      (store: option.supermarketName, replaced: done, total: option.totalIfReplaced),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _selected == null ? _overview(context) : _detail(context, _selected!),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- resumen

  Widget _header(String title, {VoidCallback? onBack}) => Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
              visualDensity: VisualDensity.compact,
            )
          else
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: AppColors.lavenderMist, shape: BoxShape.circle),
              child: const Icon(Icons.storefront_outlined, color: AppColors.brandIndigo),
            ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(title, style: AppText.screenTitle)),
        ],
      );

  Widget _overview(BuildContext context) {
    final options = _options;
    return Column(
      key: const ValueKey('overview'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Comprar todo en un solo lugar'),
        const SizedBox(height: AppSpacing.md),
        if (_failed) ...[
          Text('No pudimos calcular las opciones. Revisa tu conexión.', style: AppText.body),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ] else if (options == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Buscando productos parecidos en cada supermercado…', style: AppText.body, textAlign: TextAlign.center),
                ],
              ),
            ),
          )
        else if (options.isEmpty)
          Text('Ningún supermercado a tu alcance tiene productos de tu lista.', style: AppText.body)
        else
          ..._optionsBody(options),
      ],
    );
  }

  List<Widget> _optionsBody(List<SingleStoreOption> options) {
    final completable = options.where((o) => o.completable).toList();

    if (completable.isEmpty) {
      final best = options.first;
      return [
        Text(
          'Ningún supermercado se puede completar con productos parecidos. '
          '${best.supermarketName} es el que más tiene: ${best.itemsPriced} de ${best.itemsTotal}.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Puedes cambiar a mano los productos que faltan, o ampliar la distancia en tu perfil para ver más supermercados.', style: AppText.caption),
        const SizedBox(height: AppSpacing.lg),
        for (final o in options.take(3)) _CompactOption(option: o, onTap: () => setState(() => _selected = o)),
      ];
    }

    final recommended = completable.first;
    final others = [...completable.skip(1), ...options.where((o) => !o.completable)].take(2).toList();
    return [
      Text(
        'Para no ir a varios lados: en el supermercado que elijas cambiamos lo que no tiene por un '
        'producto parecido de ahí mismo, y tu lista queda completa.',
        style: AppText.body,
      ),
      const SizedBox(height: AppSpacing.lg),
      _RecommendedCard(option: recommended, onSee: () => setState(() => _selected = recommended)),
      if (others.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        Text('Otras opciones', style: AppText.caption),
        const SizedBox(height: AppSpacing.sm),
        for (final o in others) _CompactOption(option: o, onTap: () => setState(() => _selected = o)),
      ],
    ];
  }

  // ---------------------------------------------------------------- detalle

  Widget _detail(BuildContext context, SingleStoreOption option) {
    final applicable = option.applicable;
    final sinReemplazo = option.replacements.where((r) => r.substitute == null).toList();
    return Column(
      key: ValueKey('detail-${option.supermarketCode}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Completar en ${option.supermarketName}', onBack: _applying ? null : () => setState(() => _selected = null)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          option.completable
              ? 'Tu lista completa en ${option.supermarketName}: ${formatCop(option.totalIfReplaced!)}'
              : '${option.supermarketName} tiene ${option.itemsPriced} de ${option.itemsTotal}; '
                  'a ${sinReemplazo.length} no les encontramos un reemplazo parecido.',
          style: AppText.productName,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Se cambian ${applicable.length} ${applicable.length == 1 ? 'producto' : 'productos'}:', style: AppText.caption),
        const SizedBox(height: AppSpacing.sm),
        for (final r in applicable) _ReplacementRow(replacement: r),
        for (final r in sinReemplazo)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('${r.itemName}: sin reemplazo parecido en ${option.supermarketName}', style: AppText.caption.copyWith(color: AppColors.warning)),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_applying || applicable.isEmpty) ? null : () => _apply(option),
            icon: _applying
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                : const Icon(Icons.check_rounded),
            label: Text(_applying ? 'Aplicando…' : 'Aplicar ${applicable.length} ${applicable.length == 1 ? 'cambio' : 'cambios'}'),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
          ),
        ),
      ],
    );
  }
}

/// La opción más fácil de completar: es la única destacada (efecto Von Restorff) y
/// muestra cuánto ya está resuelto (gradiente de meta).
class _RecommendedCard extends StatelessWidget {
  final SingleStoreOption option;
  final VoidCallback onSee;

  const _RecommendedCard({required this.option, required this.onSee});

  @override
  Widget build(BuildContext context) {
    final n = option.replacements.length;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.successBorder, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(AppSpacing.chipRadius)),
            child: const Text('Recomendado', style: TextStyle(color: AppColors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(option.supermarketName, style: AppText.sectionTitle.copyWith(color: AppColors.success))),
              Text(formatCop(option.totalIfReplaced!), style: AppText.priceMain.copyWith(color: AppColors.success)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            child: LinearProgressIndicator(
              value: option.itemsPriced / option.itemsTotal,
              minHeight: 8,
              backgroundColor: AppColors.white,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${option.itemsPriced} de ${option.itemsTotal} ya los tiene · '
            '$n ${n == 1 ? 'se reemplaza' : 'se reemplazan'} por uno parecido',
            style: AppText.caption.copyWith(color: AppColors.success),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSee,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
              child: Text('Ver ${n == 1 ? 'el reemplazo' : 'los $n reemplazos'}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactOption extends StatelessWidget {
  final SingleStoreOption option;
  final VoidCallback onTap;

  const _CompactOption({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final n = option.replacements.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.mist),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.supermarketName, style: AppText.productName),
                    Text(
                      option.completable
                          ? 'Completa con $n ${n == 1 ? 'reemplazo' : 'reemplazos'}'
                          : 'Tiene ${option.itemsPriced} de ${option.itemsTotal} · no se completa',
                      style: AppText.caption.copyWith(color: option.completable ? AppColors.inkMuted : AppColors.warning),
                    ),
                  ],
                ),
              ),
              if (option.totalIfReplaced != null)
                Text(formatCop(option.totalIfReplaced!), style: AppText.priceCard.copyWith(fontSize: 14)),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplacementRow extends StatelessWidget {
  final SingleStoreReplacement replacement;

  const _ReplacementRow({required this.replacement});

  @override
  Widget build(BuildContext context) {
    final sub = replacement.substitute!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductImage(imageUrl: sub.imageUrl, size: 48),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('En vez de: ${replacement.itemName}', style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(sub.name, style: AppText.productName, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  '${formatCop(sub.unitPrice)}${replacement.quantity > 1 ? ' × ${replacement.quantity}' : ''}',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
