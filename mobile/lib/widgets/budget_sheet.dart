import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/basket.dart';

/// Lo que la persona eligió para armar una lista sugerida.
typedef BudgetChoice = ({SpendTier tier, double? budget});

/// Pregunta cuánto quiere gastar y con qué nivel antes de armar una lista
/// sugerida. Devuelve null si se cancela. `budget` es null si elige "sin límite".
Future<BudgetChoice?> showBudgetSheet(
  BuildContext context, {
  required String listName,
  required int productCount,
}) {
  return showModalBottomSheet<BudgetChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BudgetSheet(listName: listName, productCount: productCount),
  );
}

class _BudgetSheet extends StatefulWidget {
  final String listName;
  final int productCount;

  const _BudgetSheet({required this.listName, required this.productCount});

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  static const _presets = [20000, 30000, 50000, 100000];

  final _controller = TextEditingController();
  SpendTier _tier = SpendTier.medio;
  bool _noLimit = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _amount {
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    final value = int.tryParse(digits);
    return (value == null || value <= 0) ? null : value.toDouble();
  }

  bool get _ready => _noLimit || _amount != null;

  void _setAmount(int value) {
    setState(() {
      _noLimit = false;
      _controller.text = formatCop(value).substring(1); // sin el "$"
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Arma "${widget.listName}"', style: AppText.screenTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Elegimos productos reales de ${widget.productCount} básicos para que te alcance. '
              'Si no cabe todo, quitamos primero lo menos importante.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('¿Cuánto quieres gastar?', style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              enabled: !_noLimit,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixText: r'$ ',
                hintText: 'Ej. 30000',
                prefixIcon: Icon(Icons.savings_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final p in _presets)
                  ChoiceChip(
                    label: Text(formatCop(p)),
                    selected: !_noLimit && _amount == p.toDouble(),
                    onSelected: (_) => _setAmount(p),
                  ),
                ChoiceChip(
                  label: const Text('Sin límite'),
                  selected: _noLimit,
                  onSelected: (v) => setState(() {
                    _noLimit = v;
                    if (v) _controller.clear();
                  }),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Nivel de gasto', style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.sm),
            for (final tier in SpendTier.values)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  onTap: () => setState(() => _tier = tier),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: _tier == tier ? AppColors.lavenderMist : AppColors.white,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      border: Border.all(color: _tier == tier ? AppColors.brandIndigo : AppColors.mist, width: 1.4),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _tier == tier ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: _tier == tier ? AppColors.brandIndigo : AppColors.inkFaint,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tier.label, style: AppText.productName),
                              Text(tier.description, style: AppText.caption),
                            ],
                          ),
                        ),
                        Text(
                          List.filled(tier.dollars, r'$').join(),
                          style: AppText.priceCard.copyWith(
                            color: _tier == tier ? AppColors.brandIndigo : AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: _ready
                        ? () => Navigator.of(context).pop<BudgetChoice>((tier: _tier, budget: _noLimit ? null : _amount))
                        : null,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Armar lista'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
