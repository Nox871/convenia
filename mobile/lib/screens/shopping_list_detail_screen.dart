import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/budget.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/swap_suggestion.dart';
import '../models/shopping_list.dart';
import '../state/shopping_list_detail_controller.dart';
import '../state/view_status.dart';
import '../widgets/scope_note.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';
import 'add_to_list_screen.dart';

/// Pantalla de detalle de una lista: ítems, costo estimado por supermercado
/// y cuál conviene para comprarla completa.
class ShoppingListDetailScreen extends StatelessWidget {
  final int listId;

  const ShoppingListDetailScreen({super.key, required this.listId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ShoppingListDetailController(listId: listId),
      child: const _DetailScaffold(),
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShoppingListDetailController>();

    if (controller.wasDeleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(controller.detail?.name ?? 'Lista', style: AppText.screenTitle),
        actions: [
          if (controller.status == ViewStatus.loaded) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showRenameDialog(context, controller),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmDelete(context, controller),
            ),
          ],
        ],
      ),
      floatingActionButton: controller.status == ViewStatus.loaded
          ? FloatingActionButton.extended(
              onPressed: () => _addProducts(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar productos'),
            )
          : null,
      body: SafeArea(child: _DetailBody(controller: controller)),
    );
  }

  Future<void> _addProducts(BuildContext context) async {
    final entries = await Navigator.of(context).push<List<MapEntry<String, int>>>(
      MaterialPageRoute(builder: (_) => const AddToListScreen()),
    );
    if (entries == null || entries.isEmpty || !context.mounted) return;

    final controller = context.read<ShoppingListDetailController>();
    final messenger = ScaffoldMessenger.of(context);
    for (final entry in entries) {
      await controller.addItem(entry.key, quantity: entry.value);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          entries.length == 1 ? 'Se agregó 1 producto a la lista' : 'Se agregaron ${entries.length} productos a la lista',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    ShoppingListDetailController controller,
  ) async {
    final nameController = TextEditingController(text: controller.detail?.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renombrar lista'),
        content: TextField(controller: nameController, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(nameController.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await controller.rename(name);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ShoppingListDetailController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteList();
    }
  }
}

class _DetailBody extends StatelessWidget {
  final ShoppingListDetailController controller;

  const _DetailBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    switch (controller.status) {
      case ViewStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ViewStatus.error:
        return ErrorResultsView(onRetry: controller.retry);
      case ViewStatus.empty:
        return const EmptyResultsView(title: 'Lista no encontrada');
      case ViewStatus.loaded:
        final detail = controller.detail!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.horizontalPage,
            AppSpacing.md,
            AppSpacing.horizontalPage,
            AppSpacing.xxxl * 3,
          ),
          children: [
            if (detail.items.isNotEmpty) ...[
              ScopeNote(padded: false, onChanged: controller.retry),
              const SizedBox(height: AppSpacing.md),
            ],
            if (detail.items.isNotEmpty && controller.cost != null)
              _SummaryBanner(
                cost: controller.cost!,
                distributedPlan: controller.distributedPlanWorthShowing ? controller.distributedPlan : null,
              ),
            if (detail.items.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _BudgetCard(
                budget: detail.budget,
                cost: controller.cost,
                distributedPlan: controller.distributedPlan,
                onChange: controller.setBudget,
              ),
              if (controller.isOverBudget && controller.swaps.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _SwapSection(controller: controller),
              ],
            ],
            if (detail.items.isNotEmpty && controller.cost != null) ...[
              const SizedBox(height: AppSpacing.xl),
              _CostSection(cost: controller.cost!, budget: detail.budget),
            ],
            if (controller.distributedPlanWorthShowing) ...[
              const SizedBox(height: AppSpacing.md),
              _DistributedPlanSection(plan: controller.distributedPlan!),
            ],
            if (detail.items.isNotEmpty) const SizedBox(height: AppSpacing.xl),
            Text(
              detail.items.isEmpty
                  ? 'Productos'
                  : 'Productos (${detail.items.length})',
              style: AppText.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.md),
            if (detail.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  'Toca "Agregar productos" y escribe, di o fotografía lo que necesitas.',
                  style: AppText.body,
                ),
              ),
            ...detail.items.map((item) => _ItemTile(item: item, controller: controller)),
          ],
        );
    }
  }
}

/// La respuesta corta a "¿dónde compro esta lista?", arriba de todo: el
/// mejor supermercado con la lista COMPLETA y, si conviene, cuánto cuesta
/// repartirla. Justo debajo van el presupuesto, el desglose por supermercado
/// y la compra distribuida; los productos vienen después.
class _SummaryBanner extends StatelessWidget {
  final ShoppingListCostResponse cost;
  final ShoppingListDistributedResponse? distributedPlan;

  const _SummaryBanner({required this.cost, required this.distributedPlan});

  @override
  Widget build(BuildContext context) {
    final bestCode = cost.bestSupermarketCode;
    final best = bestCode == null
        ? null
        : cost.costs.where((c) => c.supermarketCode == bestCode).firstOrNull;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: best != null ? AppColors.successSurface : AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: best != null ? AppColors.successBorder : AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (best != null) ...[
            Text('Te conviene comprarla completa en', style: AppText.caption),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(best.supermarketName, style: AppText.sectionTitle.copyWith(color: AppColors.success)),
                ),
                Text(
                  best.totalCost != null ? formatCop(best.totalCost!) : '',
                  style: AppText.priceMain.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ] else
            Text(
              'Ningún supermercado tiene toda tu lista con precio todavía. '
              'Abajo ves cuánto tiene cada uno.',
              style: AppText.body,
            ),
          if (distributedPlan?.totalCost != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Repartida entre varios supermercados: ${formatCop(distributedPlan!.totalCost!)}',
              style: AppText.body.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _CostSection extends StatelessWidget {
  final ShoppingListCostResponse cost;
  final int? budget;

  const _CostSection({required this.cost, this.budget});

  @override
  Widget build(BuildContext context) {
    if (cost.costs.isEmpty) {
      return const SizedBox.shrink();
    }

    final sorted = [...cost.costs]..sort((a, b) {
      if (a.totalCost == null && b.totalCost == null) return 0;
      if (a.totalCost == null) return 1;
      if (b.totalCost == null) return -1;
      return a.totalCost!.compareTo(b.totalCost!);
    });

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Costo por supermercado', style: AppText.sectionTitle),
          if (cost.bestSupermarketCode != null) ...[
            const SizedBox(height: 4),
            Text(
              'Te conviene comprarla completa en '
              '${sorted.firstWhere((c) => c.supermarketCode == cost.bestSupermarketCode).supermarketName}.',
              style: const TextStyle(fontSize: 13, color: AppColors.success),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ...sorted.map((c) {
            final isBest = c.supermarketCode == cost.bestSupermarketCode;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.supermarketName,
                          style: AppText.body.copyWith(
                            fontWeight: isBest ? FontWeight.w700 : FontWeight.w400,
                            color: isBest ? AppColors.success : AppColors.inkMuted,
                          ),
                        ),
                        if (budget != null && c.isComplete && c.totalCost != null)
                          _BudgetCaption(comparison: compareToBudget(budget, c.totalCost)!),
                      ],
                    ),
                  ),
                  if (!c.isComplete)
                    Container(
                      margin: const EdgeInsets.only(right: AppSpacing.sm),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warningSurface,
                        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                      ),
                      child: Text(
                        'Incompleto ${c.itemsPriced}/${c.itemsTotal}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  Text(
                    c.totalCost != null ? formatCop(c.totalCost!) : 'Sin datos',
                    style: AppText.priceCard.copyWith(
                      fontSize: 14,
                      color: isBest ? AppColors.success : AppColors.ink,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// "¿Cuánto me costaría y dónde puedo hacerla?" cuando dividir la compra
/// entre varios supermercados sale más barato que comprarla completa en uno
/// solo. Sólo se renderiza cuando `distributedPlanWorthShowing` es true --
/// nunca se ofrece si no hay un ahorro real (ruido).
class _DistributedPlanSection extends StatefulWidget {
  final ShoppingListDistributedResponse plan;

  const _DistributedPlanSection({required this.plan});

  @override
  State<_DistributedPlanSection> createState() => _DistributedPlanSectionState();
}

class _DistributedPlanSectionState extends State<_DistributedPlanSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.lavenderMist,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                const Icon(Icons.call_split_rounded, size: 18, color: AppColors.brandIndigo),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Comprar distribuido te sale en '
                    '${plan.totalCost != null ? formatCop(plan.totalCost!) : '—'}',
                    style: AppText.sectionTitle.copyWith(color: AppColors.brandIndigo),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppColors.brandIndigo,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.md),
            for (final stop in plan.stops) ...[
              Text(
                '${stop.supermarketName} · ${formatCop(stop.subtotal)}',
                style: AppText.productName,
              ),
              const SizedBox(height: 2),
              ...stop.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.md, bottom: 2),
                  child: Text(
                    '${item.quantity} × ${item.name}',
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (plan.unpricedItemIds.isNotEmpty)
              Text(
                '${plan.unpricedItemIds.length} producto(s) sin precio en ningún supermercado '
                'todavía.',
                style: AppText.caption,
              ),
          ],
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final ShoppingListItem item;
  final ShoppingListDetailController controller;

  const _ItemTile({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.mist),
      ),
      child: Row(
        children: [
          ProductImage(imageUrl: item.imageUrl, size: 56),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppText.productName, maxLines: 3, overflow: TextOverflow.ellipsis),
                if (item.brand != null) Text(item.brand!, style: AppText.caption),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    _RoundButton(
                      icon: Icons.remove_rounded,
                      onPressed: item.quantity > 1
                          ? () => controller.updateQuantity(item.id, item.quantity - 1)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Text('${item.quantity}', style: AppText.productName),
                    ),
                    _RoundButton(
                      icon: Icons.add_rounded,
                      onPressed: () => controller.updateQuantity(item.id, item.quantity + 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar de la lista',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.inkFaint),
            onPressed: () => controller.removeItem(item.id),
          ),
        ],
      ),
    );
  }
}

/// Botón redondo pequeño (cantidad +/-): más compacto que un IconButton
/// normal, para que el nombre del producto tenga espacio.
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _RoundButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return InkResponse(
      onTap: onPressed,
      radius: 20,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? AppColors.lavenderMist : AppColors.mist,
        ),
        child: Icon(icon, size: 18, color: enabled ? AppColors.brandIndigo : AppColors.inkFaint),
      ),
    );
  }
}

/// "Te sobran $X" / "Te pasas por $X" en una línea chica.
class _BudgetCaption extends StatelessWidget {
  final BudgetComparison comparison;

  /// Aclara contra qué total se compara cuando no es el de un solo
  /// supermercado (por ejemplo, "Repartida entre varios supermercados: ").
  final String prefix;

  const _BudgetCaption({required this.comparison, this.prefix = ''});

  @override
  Widget build(BuildContext context) {
    final within = comparison.isWithin;
    return Text(
      within
          ? '${prefix}te sobran ${formatCop(comparison.difference)}'
          : '${prefix}te pasas por ${formatCop(-comparison.difference)}',
      style: AppText.caption.copyWith(color: within ? AppColors.success : AppColors.error),
    );
  }
}

/// Presupuesto de ESTA lista: cuánto quiere gastar la persona y cómo se
/// compara contra lo que cuesta comprarla. Sin presupuesto muestra una
/// invitación a definirlo; nunca se inventa uno.
class _BudgetCard extends StatelessWidget {
  final int? budget;
  final ShoppingListCostResponse? cost;
  final ShoppingListDistributedResponse? distributedPlan;
  final Future<void> Function(int? budget) onChange;

  const _BudgetCard({
    required this.budget,
    required this.cost,
    required this.distributedPlan,
    required this.onChange,
  });

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: budget?.toString() ?? '');
    final result = await showDialog<_BudgetDialogResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Presupuesto de la lista'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Cuánto quieres gastar', prefixText: '\$ '),
        ),
        actions: [
          if (budget != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(const _BudgetDialogResult.remove()),
              child: const Text('Quitar'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final digits = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
              Navigator.of(dialogContext).pop(
                digits.isEmpty ? null : _BudgetDialogResult.set(int.parse(digits)),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await onChange(result.remove ? null : result.value);
  }

  @override
  Widget build(BuildContext context) {
    final current = budget;

    if (current == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.mist),
        ),
        child: Row(
          children: [
            const Icon(Icons.savings_outlined, color: AppColors.brandIndigo),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                '¿Cuánto quieres gastar? Defínelo para ver cuánto te sobra o te pasas.',
                style: AppText.body,
              ),
            ),
            TextButton(onPressed: () => _edit(context), child: const Text('Definir')),
          ],
        ),
      );
    }

    final complete = cost == null ? null : compareToBudget(current, completeListTotal(cost!));
    final distributed = compareToBudget(current, distributedTotal(distributedPlan));
    final shown = complete ?? distributed;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, color: AppColors.brandIndigo, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Presupuesto ${formatCop(current)}', style: AppText.sectionTitle),
              ),
              IconButton(
                tooltip: 'Editar presupuesto',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _edit(context),
              ),
            ],
          ),
          if (shown != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
              child: LinearProgressIndicator(
                value: shown.usedFraction.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.mist,
                color: shown.isWithin ? AppColors.success : AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BudgetCaption(
              comparison: shown,
              prefix: complete == null ? 'Repartida entre varios supermercados: ' : '',
            ),
            if (complete != null && distributed != null && distributed.total < complete.total)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  distributed.isWithin
                      ? 'Repartida: te sobrarían ${formatCop(distributed.difference)}'
                      : 'Repartida: te pasarías por ${formatCop(-distributed.difference)}',
                  style: AppText.caption,
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Todavía no hay un total completo con precio para comparar '
                '(faltan productos por cotizar).',
                style: AppText.caption,
              ),
            ),
        ],
      ),
    );
  }
}

class _BudgetDialogResult {
  final int value;
  final bool remove;

  const _BudgetDialogResult.set(this.value) : remove = false;
  const _BudgetDialogResult.remove() : value = 0, remove = true;
}

/// "Cómo ahorrar": cuando la lista se pasa del presupuesto, propone cambiar
/// algunos productos por otros del MISMO tipo y tamaño que son más baratos.
/// Nada se cambia solo: cada cambio se aplica con su botón.
class _SwapSection extends StatelessWidget {
  final ShoppingListDetailController controller;

  const _SwapSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final swaps = controller.swaps;
    final totalSaving = swaps.fold<double>(0, (sum, s) => sum + s.savingTotal);
    final over = controller.budgetComparison;
    final gap = over == null ? 0.0 : -over.difference;
    final closesTheGap = totalSaving >= gap;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, color: AppColors.brandIndigo, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Cómo ahorrar', style: AppText.sectionTitle)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            closesTheGap
                ? 'Con estos cambios podrías ahorrar unos ${formatCop(totalSaving)} y quedar dentro de tu presupuesto.'
                : 'Con estos cambios podrías ahorrar unos ${formatCop(totalSaving)}; aún así te pasarías por '
                    '${formatCop(gap - totalSaving)}.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final swap in swaps) ...[
            _SwapTile(swap: swap, onApply: () => _apply(context, swap)),
            if (swap != swaps.last) const Divider(height: AppSpacing.xl),
          ],
        ],
      ),
    );
  }

  Future<void> _apply(BuildContext context, SwapSuggestion swap) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.applySwap(swap);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Cambiamos «${swap.itemName}» por «${swap.alternative.name}».' : 'No pudimos hacer el cambio.'),
      ),
    );
  }
}

class _SwapTile extends StatelessWidget {
  final SwapSuggestion swap;
  final VoidCallback onApply;

  const _SwapTile({required this.swap, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final alt = swap.alternative;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductImage(imageUrl: alt.imageUrl, size: 48),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('En vez de', style: AppText.caption),
              Text(swap.itemName, style: AppText.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Mejor', style: AppText.caption),
              Text(alt.name, style: AppText.productName, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${formatCop(swap.currentUnitPrice)} → ${formatCop(alt.unitPrice)} · en ${alt.supermarketName}'
                '${swap.quantity > 1 ? ' · x${swap.quantity}' : ''}',
                style: AppText.caption,
              ),
              Text(
                'Ahorras ${formatCop(swap.savingTotal)}',
                style: AppText.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(onPressed: onApply, child: const Text('Cambiar')),
      ],
    );
  }
}
