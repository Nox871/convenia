import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/shopping_list.dart';
import '../state/shopping_list_detail_controller.dart';
import '../state/view_status.dart';
import '../widgets/state_views.dart';
import 'pick_product_screen.dart';

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
              onPressed: () async {
                final productId = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const PickProductScreen()),
                );
                if (productId != null && context.mounted) {
                  await context.read<ShoppingListDetailController>().addItem(productId);
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar producto'),
            )
          : null,
      body: SafeArea(child: _DetailBody(controller: controller)),
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
            AppSpacing.xxxl * 2,
          ),
          children: [
            if (controller.cost != null) _CostSection(cost: controller.cost!),
            if (controller.distributedPlanWorthShowing) ...[
              const SizedBox(height: AppSpacing.md),
              _DistributedPlanSection(plan: controller.distributedPlan!),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text('Productos', style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.md),
            if (detail.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  'Agrega productos con el botón "Agregar producto".',
                  style: AppText.body,
                ),
              ),
            ...detail.items.map((item) => _ItemTile(item: item, controller: controller)),
          ],
        );
    }
  }
}

class _CostSection extends StatelessWidget {
  final ShoppingListCostResponse cost;

  const _CostSection({required this.cost});

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
          Text('Costo estimado por supermercado', style: AppText.sectionTitle),
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
                    child: Text(
                      c.supermarketName,
                      style: AppText.body.copyWith(
                        fontWeight: isBest ? FontWeight.w700 : FontWeight.w400,
                        color: isBest ? AppColors.success : AppColors.inkMuted,
                      ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppText.productName, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (item.brand != null) Text(item.brand!, style: AppText.caption),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: item.quantity > 1
                ? () => controller.updateQuantity(item.id, item.quantity - 1)
                : null,
          ),
          Text('${item.quantity}', style: AppText.productName),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => controller.updateQuantity(item.id, item.quantity + 1),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.inkFaint),
            onPressed: () => controller.removeItem(item.id),
          ),
        ],
      ),
    );
  }
}
