import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/budget.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/swap_suggestion.dart';
import '../models/shopping_list.dart';
import '../state/shopping_list_detail_controller.dart';
import '../state/view_status.dart';
import '../widgets/app_sheets.dart';
import '../widgets/product_image.dart';
import '../widgets/product_picker_sheet.dart';
import '../widgets/scope_note.dart';
import '../widgets/single_store_sheet.dart';
import '../widgets/state_views.dart';
import 'add_to_list_screen.dart';

/// Pantalla de detalle de una lista: ítems, costo estimado por supermercado
/// y cuál conviene para comprarla completa.
class ShoppingListDetailScreen extends StatelessWidget {
  final int listId;

  /// Para pruebas: un controlador ya armado (con un repositorio falso).
  final ShoppingListDetailController? controller;

  const ShoppingListDetailScreen(
      {super.key, required this.listId, this.controller});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => controller ?? ShoppingListDetailController(listId: listId),
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

    return ScopeReloader(
      onChanged: controller.retry,
      child: Scaffold(
        appBar: AppBar(
          title: Text(controller.detail?.name ?? 'Lista',
              style: AppText.screenTitle),
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
        bottomNavigationBar: controller.status == ViewStatus.loaded
            ? _BottomBar(
                controller: controller, onAdd: () => _addProducts(context))
            : null,
        body: SafeArea(child: _DetailBody(controller: controller)),
      ),
    );
  }

  Future<void> _addProducts(BuildContext context) async {
    final result = await Navigator.of(context).push<AddToListResult>(
      MaterialPageRoute(builder: (_) => const AddToListScreen()),
    );
    if (result == null || result.entries.isEmpty || !context.mounted) return;
    final entries = result.entries;

    final controller = context.read<ShoppingListDetailController>();
    final messenger = ScaffoldMessenger.of(context);
    for (final entry in entries) {
      await controller.addItem(entry.key, quantity: entry.value);
    }
    // El presupuesto que se eligió al armar la lista sugerida queda guardado en la
    // lista (si ya tenía uno, no se pisa): si no, la pantalla pediría "Definir" otra vez.
    if (result.budget != null && controller.detail?.budget == null) {
      await controller.setBudget(result.budget);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          entries.length == 1
              ? 'Se agregó 1 producto a la lista'
              : 'Se agregaron ${entries.length} productos a la lista',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    ShoppingListDetailController controller,
  ) async {
    final name = await showTextSheet(
      context,
      title: 'Renombrar lista',
      initial: controller.detail?.name ?? '',
      label: 'Nombre de la lista',
      icon: Icons.drive_file_rename_outline_rounded,
    );
    if (name != null && name.isNotEmpty) {
      await controller.rename(name);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ShoppingListDetailController controller,
  ) async {
    final confirmed = await showConfirmSheet(
      context,
      title: 'Eliminar esta lista',
      message:
          'Se borran la lista y sus productos. Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
    );
    if (confirmed) {
      await controller.deleteList();
    }
  }
}

/// "Comprar todo en un solo lugar": abre las opciones y, al aplicar, muestra el cierre.
Future<void> _openSingleStore(BuildContext context, ShoppingListDetailController controller) async {
  final messenger = ScaffoldMessenger.of(context);
  final done = await showSingleStoreSheet(context, controller);
  if (done == null) return;
  // Momento de cierre: lo que la persona se lleva es que ya puede ir a UN solo lugar.
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.successBorder),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '¡Tu lista ya está completa en ${done.store}!'
              '${done.total != null ? ' ${formatCop(done.total!)}' : ''}',
            ),
          ),
        ],
      ),
    ),
  );
}

/// Abre "Cómo ahorrar" en una hoja: cambios por productos parecidos y más baratos.
void _openSavings(BuildContext context, ShoppingListDetailController controller) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => ChangeNotifierProvider.value(value: controller, child: const _SavingsSheet()),
  );
}

class _SavingsSheet extends StatelessWidget {
  const _SavingsSheet();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShoppingListDetailController>();
    final empty = controller.swaps.isEmpty;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: AppColors.lavenderMist, shape: BoxShape.circle),
                  child: const Icon(Icons.swap_horiz_rounded, color: AppColors.brandIndigo),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text('Cómo ahorrar', style: AppText.screenTitle)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (empty) ...[
              Text('Ya no hay más cambios por hacer.', style: AppText.body),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
                child: const Text('Listo'),
              ),
            ] else
              _SwapSection(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// Barra fija de abajo: deja claro que la lista se guarda sola y da un cierre
/// ("Listo"), además de seguir agregando.
class _BottomBar extends StatelessWidget {
  final ShoppingListDetailController controller;
  final VoidCallback onAdd;

  const _BottomBar({required this.controller, required this.onAdd});

  String _savedText() {
    final at = controller.savedAt;
    if (at == null) return 'Se guarda automáticamente';
    final seconds = DateTime.now().difference(at).inSeconds;
    if (seconds < 60) return 'Guardado hace un momento';
    final minutes = seconds ~/ 60;
    return minutes == 1 ? 'Guardado hace 1 min' : 'Guardado hace $minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final count = controller.detail?.items.length ?? 0;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.mist)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.horizontalPage,
              AppSpacing.sm, AppSpacing.horizontalPage, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_done_outlined,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_savedText()} · $count ${count == 1 ? 'producto' : 'productos'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: AppColors.success),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Agregar'),
                      style: OutlinedButton.styleFrom(
                          minimumSize:
                              const Size.fromHeight(AppSpacing.buttonHeight)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(controller.finishSummary()),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Listo'),
                      style: ElevatedButton.styleFrom(
                          minimumSize:
                              const Size.fromHeight(AppSpacing.buttonHeight)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
        final cost = controller.cost;
        final plan = controller.distributedPlan;
        final hasItems = detail.items.isNotEmpty;
        // Sólo se cuentan supermercados que tienen algo de la lista: uno sin
        // ningún precio ("Sin datos") no aporta nada para decidir.
        final pricedStores =
            cost?.costs.where((c) => c.totalCost != null).toList() ??
                const <SupermarketCost>[];
        final totalSaving =
            controller.swaps.fold<double>(0, (sum, s) => sum + s.savingTotal);

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.horizontalPage,
            AppSpacing.md,
            AppSpacing.horizontalPage,
            AppSpacing.xxl,
          ),
          children: [
            // 1) La respuesta corta y el presupuesto, compactos.
            if (hasItems && cost != null)
              _SummaryBanner(
                cost: cost,
                distributedPlan:
                    controller.distributedPlanWorthShowing ? plan : null,
                // Si ninguna tienda tiene toda la lista, se ofrece completarla en UNA con
                // reemplazos parecidos (nadie quiere ir a tres supermercados).
                onSingleStore: (detail.items.length >= 2 && pricedStores.isNotEmpty)
                    ? () => _openSingleStore(context, controller)
                    : null,
              ),
            if (hasItems) ...[
              const SizedBox(height: AppSpacing.sm),
              _BudgetCard(
                budget: detail.budget,
                cost: cost,
                distributedPlan: plan,
                onChange: controller.setBudget,
                // Si te pasas del presupuesto, el camino para ahorrar va AQUÍ, junto al aviso.
                savingsLabel: (controller.isOverBudget && controller.swaps.isNotEmpty)
                    ? 'Cómo ahorrar · hasta ${formatCop(totalSaving)}'
                    : null,
                onSavings: (controller.isOverBudget && controller.swaps.isNotEmpty)
                    ? () => _openSavings(context, controller)
                    : null,
              ),
            ],

            // 2) Lo más importante: los productos.
            const SizedBox(height: AppSpacing.lg),
            Text(hasItems ? 'Productos (${detail.items.length})' : 'Productos',
                style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.md),
            if (!hasItems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  'Toca "Agregar" y escribe, di o fotografía lo que necesitas.',
                  style: AppText.body,
                ),
              ),
            ...detail.items
                .map((item) => _ItemTile(item: item, controller: controller)),

            // 3) El detalle, plegado: se abre sólo si se quiere.
            if (hasItems) ...[
              const SizedBox(height: AppSpacing.md),
              if (pricedStores.isNotEmpty)
                _Collapsible(
                  icon: Icons.storefront_outlined,
                  title: 'Comparar supermercados',
                  subtitle:
                      '${pricedStores.length} ${pricedStores.length == 1 ? 'supermercado' : 'supermercados'}'
                      '${cost?.bestSupermarketCode != null ? ' · el mejor: ${pricedStores.firstWhere((c) => c.supermarketCode == cost!.bestSupermarketCode).supermarketName}' : ''}',
                  child: _CostSection(
                      cost: cost!, budget: detail.budget, items: detail.items),
                ),
              if (controller.distributedPlanWorthShowing && plan != null)
                _Collapsible(
                  icon: Icons.call_split_rounded,
                  title: 'Qué comprar en cada supermercado',
                  subtitle: 'Repartida en ${plan.stops.length} supermercados · '
                      '${plan.totalCost != null ? formatCop(plan.totalCost!) : '—'}',
                  child: _DistributedPlanSection(plan: plan),
                ),
            ],
          ],
        );
    }
  }
}

/// Sección plegable: título y una línea de resumen; el contenido sólo se ve al
/// abrirla. Mantiene la pantalla corta sin esconder la información.
class _Collapsible extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _Collapsible({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
            color: AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(widget.icon, color: AppColors.brandIndigo, size: 22),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: AppText.productName),
                        Text(widget.subtitle,
                            style: AppText.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.inkMuted),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// La respuesta corta a "¿dónde compro esta lista?", arriba de todo: el
/// mejor supermercado con la lista COMPLETA y, si conviene, cuánto cuesta
/// repartirla. Justo debajo van el presupuesto, el desglose por supermercado
/// y la compra distribuida; los productos vienen después.
class _SummaryBanner extends StatelessWidget {
  final ShoppingListCostResponse cost;
  final ShoppingListDistributedResponse? distributedPlan;
  final VoidCallback? onSingleStore;

  const _SummaryBanner({
    required this.cost,
    required this.distributedPlan,
    this.onSingleStore,
  });

  @override
  Widget build(BuildContext context) {
    final bestCode = cost.bestSupermarketCode;
    final best = bestCode == null
        ? null
        : cost.costs.where((c) => c.supermarketCode == bestCode).firstOrNull;
    final planTotal = distributedPlan?.totalCost;
    final stores =
        distributedPlan?.stops.map((s) => s.supermarketName).toList() ??
            const <String>[];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: best != null ? AppColors.successSurface : AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
            color: best != null ? AppColors.successBorder : AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (best != null) ...[
            Text('Te conviene comprar tu lista completa en:',
                style: AppText.caption),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(best.supermarketName,
                      style: AppText.sectionTitle
                          .copyWith(color: AppColors.success)),
                ),
                Text(
                  best.totalCost != null ? formatCop(best.totalCost!) : '',
                  style: AppText.priceMain.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ] else
            Text(
              planTotal != null && stores.length > 1
                  ? 'Ningún supermercado tiene toda tu lista. Lo más barato es repartirla.'
                  : 'Ningún supermercado tiene toda tu lista con precio todavía.',
              style: AppText.body,
            ),
          if (planTotal != null && stores.length > 1) ...[
            const SizedBox(height: 2),
            Text(
              'Repartida entre ${stores.join(' y ')}: ${formatCop(planTotal)}',
              style: AppText.body.copyWith(color: AppColors.inkMuted),
            ),
          ],
          // Siempre disponible, pero discreto: es una alternativa, no la acción principal.
          if (onSingleStore != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: AppColors.mist),
            InkWell(
              onTap: onSingleStore,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 18, color: AppColors.brandIndigo),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        best == null ? 'Comprar todo en un solo lugar' : 'Ver otras tiendas para comprar todo junto',
                        style: AppText.body.copyWith(color: AppColors.brandIndigo, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.brandIndigo),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CostSection extends StatefulWidget {
  final ShoppingListCostResponse cost;
  final int? budget;
  final List<ShoppingListItem> items;

  const _CostSection({required this.cost, this.budget, this.items = const []});

  @override
  State<_CostSection> createState() => _CostSectionState();
}

class _CostSectionState extends State<_CostSection> {
  final Set<String> _expanded = {};

  List<String> _missingNames(SupermarketCost c) => [
        for (final id in c.missingItemIds)
          widget.items.where((i) => i.id == id).map((i) => i.name).firstOrNull,
      ].whereType<String>().toList();

  @override
  Widget build(BuildContext context) {
    final cost = widget.cost;
    // Un supermercado sin ningún precio de la lista ("Sin datos") no se muestra.
    final sorted = cost.costs.where((c) => c.totalCost != null).toList()
      ..sort((a, b) => a.totalCost!.compareTo(b.totalCost!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in sorted) ...[
          Builder(builder: (context) {
            final isBest = c.supermarketCode == cost.bestSupermarketCode;
            final missing = c.isComplete ? <String>[] : _missingNames(c);
            final open = _expanded.contains(c.supermarketCode);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: InkWell(
                onTap: missing.isEmpty
                    ? null
                    : () => setState(() => open
                        ? _expanded.remove(c.supermarketCode)
                        : _expanded.add(c.supermarketCode)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.supermarketName,
                                style: AppText.body.copyWith(
                                  fontWeight: isBest
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isBest
                                      ? AppColors.success
                                      : AppColors.ink,
                                ),
                              ),
                              Text(
                                c.isComplete
                                    ? 'Tiene los ${c.itemsTotal} productos'
                                    : 'Tiene ${c.itemsPriced} de ${c.itemsTotal} productos'
                                        '${c.itemsTotal - c.itemsPriced == 1 ? ' · ¡solo le falta 1!' : ''}',
                                style: AppText.caption.copyWith(
                                  // A un solo producto de la meta se resalta: el avance
                                  // cercano motiva más que una lista de faltantes.
                                  color: c.isComplete
                                      ? AppColors.success
                                      : (c.itemsTotal - c.itemsPriced == 1
                                          ? AppColors.brandIndigo
                                          : AppColors.warning),
                                  fontWeight: c.itemsTotal - c.itemsPriced == 1 ? FontWeight.w700 : null,
                                ),
                              ),
                              if (widget.budget != null && c.isComplete)
                                _BudgetCaption(
                                    comparison: compareToBudget(
                                        widget.budget, c.totalCost)!),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatCop(c.totalCost!),
                              style: AppText.priceCard.copyWith(
                                fontSize: 14,
                                color:
                                    isBest ? AppColors.success : AppColors.ink,
                              ),
                            ),
                            if (!c.isComplete)
                              Text('Total parcial',
                                  style: AppText.caption
                                      .copyWith(color: AppColors.warning)),
                          ],
                        ),
                      ],
                    ),
                    if (missing.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: open
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Le falta:',
                                      style: AppText.caption.copyWith(
                                          fontWeight: FontWeight.w700)),
                                  for (final name in missing)
                                    Text('• $name', style: AppText.caption),
                                  Text('Ocultar',
                                      style: AppText.caption.copyWith(
                                          color: AppColors.brandIndigo)),
                                ],
                              )
                            : Text(
                                'Le falta: ${missing.take(2).join(', ')}'
                                '${missing.length > 2 ? ' y ${missing.length - 2} más · ver cuáles' : ''}',
                                style: AppText.caption.copyWith(
                                  color: missing.length > 2
                                      ? AppColors.brandIndigo
                                      : AppColors.inkMuted,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

/// "¿Cuánto me costaría y dónde puedo hacerla?" cuando dividir la compra
/// entre varios supermercados sale más barato que comprarla completa en uno
/// solo. Sólo se renderiza cuando `distributedPlanWorthShowing` es true --
/// nunca se ofrece si no hay un ahorro real (ruido).
class _DistributedPlanSection extends StatelessWidget {
  final ShoppingListDistributedResponse plan;

  const _DistributedPlanSection({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cada producto en donde sale más barato:', style: AppText.caption),
        const SizedBox(height: AppSpacing.sm),
        for (final stop in plan.stops) ...[
          Text('${stop.supermarketName} · ${formatCop(stop.subtotal)}',
              style: AppText.productName),
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
            '${plan.unpricedItemIds.length} producto(s) sin precio en ningún supermercado todavía.',
            style: AppText.caption,
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final ShoppingListItem item;
  final ShoppingListDetailController controller;

  const _ItemTile({required this.item, required this.controller});

  /// Primera palabra del nombre ("Huevo sorpresa OZMO" -> "huevo"): una búsqueda
  /// amplia, para poder elegir cualquier producto parecido y no sólo este.
  String get _genericQuery {
    final word = item.name
        .trim()
        .split(RegExp(r'\s+'))
        .firstWhere((w) => w.length >= 3, orElse: () => item.name);
    return word.toLowerCase();
  }

  Future<void> _change(BuildContext context) async {
    final picked =
        await showProductPicker(context, initialQuery: _genericQuery);
    if (picked == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.replaceItem(item, picked.id);
    messenger.showSnackBar(
      SnackBar(
          content: Text(ok
              ? 'Cambiado por "${picked.name}"'
              : 'No pudimos cambiarlo. Intenta de nuevo.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignment = controller.assignments[item.id];
    final unpriced = controller.unpricedItemIds.contains(item.id);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.mist),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProductImage(imageUrl: item.imageUrl, size: 80, fillHeight: true),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              // La X de quitar flota arriba a la derecha en vez de ocupar una columna:
              // así queda ancho para la cantidad y "Cambiar" en una sola fila.
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 26),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.brand != null && item.brand!.trim().isNotEmpty)
                              Text(item.brand!.toUpperCase(), style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(item.name, style: AppText.productName, maxLines: 3, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (assignment != null)
                        _StoreChip(label: '${assignment.store} · ${formatCop(assignment.subtotal)}', best: true)
                      else if (unpriced)
                        // No es un dato perdido: ese producto es de un supermercado que no está
                        // a tu alcance. El aviso es un atajo para cambiarlo por uno que sí esté.
                        _StoreChip(label: 'No está en tus tiendas · Cambiar', best: false, onTap: () => _change(context)),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RoundButton(
                                icon: Icons.remove_rounded,
                                onPressed: item.quantity > 1 ? () => controller.updateQuantity(item.id, item.quantity - 1) : null,
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
                          TextButton.icon(
                            onPressed: () => _change(context),
                            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                            label: const Text('Cambiar'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: IconButton(
                      tooltip: 'Quitar de la lista',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.inkFaint),
                      onPressed: () => controller.removeItem(item.id),
                    ),
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

/// En qué supermercado conviene comprar este producto (verde) o por qué no hay
/// dónde (gris).
class _StoreChip extends StatelessWidget {
  final String label;
  final bool best;
  final VoidCallback? onTap;

  const _StoreChip({required this.label, required this.best, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Neutral a propósito: si cada producto lleva una etiqueta verde, ninguna
    // destaca. El verde queda para lo que de verdad importa (el mejor total); el
    // aviso de "no está en tus tiendas" sí llama la atención porque pide una acción.
    final Color bg = best ? AppColors.lavenderMist : AppColors.warningSurface;
    final Color fg = best ? AppColors.brandIndigo : AppColors.warning;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(best ? Icons.storefront_outlined : Icons.info_outline_rounded, size: 13, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
            ),
          ],
        ),
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
        child: Icon(icon,
            size: 18,
            color: enabled ? AppColors.brandIndigo : AppColors.inkFaint),
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
      style: AppText.caption
          .copyWith(color: within ? AppColors.success : AppColors.error),
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
  final String? savingsLabel;
  final VoidCallback? onSavings;

  const _BudgetCard({
    required this.budget,
    required this.cost,
    required this.distributedPlan,
    required this.onChange,
    this.savingsLabel,
    this.onSavings,
  });

  Future<void> _edit(BuildContext context) async {
    final result = await showAmountSheet(
      context,
      title: 'Presupuesto de la lista',
      subtitle: 'Te avisamos cuánto te sobra o cuánto te pasas.',
      initial: budget,
      allowRemove: budget != null,
    );
    if (result == null) return;
    await onChange(result.remove ? null : result.value);
  }

  @override
  Widget build(BuildContext context) {
    final current = budget;

    if (current == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: () => _edit(context),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.mist),
          ),
          child: Row(
            children: [
              const Icon(Icons.savings_outlined,
                  color: AppColors.brandIndigo, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Sin presupuesto', style: AppText.body)),
              const Text('Definir',
                  style: TextStyle(
                      color: AppColors.brandIndigo,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    final complete = cost == null
        ? null
        : compareToBudget(current, completeListTotal(cost!));
    final distributed =
        compareToBudget(current, distributedTotal(distributedPlan));
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
              const Icon(Icons.savings_outlined,
                  color: AppColors.brandIndigo, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Presupuesto ${formatCop(current)}',
                    style: AppText.sectionTitle),
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
              prefix: complete == null
                  ? 'Repartida entre varios supermercados: '
                  : '',
            ),
            if (complete != null &&
                distributed != null &&
                distributed.total < complete.total)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  distributed.isWithin
                      ? 'Repartida: te sobrarían ${formatCop(distributed.difference)}'
                      : 'Repartida: te pasarías por ${formatCop(-distributed.difference)}',
                  style: AppText.caption,
                ),
              ),
            if (onSavings != null && savingsLabel != null) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onSavings,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: Text(savingsLabel!),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.lavenderMist,
                    foregroundColor: AppColors.brandIndigo,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
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

/// "Cómo ahorrar": cuando la lista se pasa del presupuesto, propone cambiar
/// algunos productos por otros del MISMO tipo y tamaño que son más baratos.
/// Nada se cambia solo: cada cambio se aplica con su botón.
class _SwapSection extends StatefulWidget {
  final ShoppingListDetailController controller;

  const _SwapSection({required this.controller});

  @override
  State<_SwapSection> createState() => _SwapSectionState();
}

class _SwapSectionState extends State<_SwapSection> {
  bool _verOtrasTiendas = false;

  ShoppingListDetailController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final todas = controller.swaps;
    // Si UNA tienda ya tiene toda la lista, los cambios que llevan a otra tienda la
    // volverían a repartir: se separan y se ofrecen aparte, con aviso.
    final unaTienda = controller.cost?.bestSupermarketCode;
    final unaTiendaNombre = controller.cost?.costs
        .where((c) => c.supermarketCode == unaTienda)
        .firstOrNull
        ?.supermarketName;
    final enLaMisma = unaTienda == null
        ? todas
        : todas.where((s) => s.alternative.supermarketCode == unaTienda).toList();
    final enOtras = unaTienda == null
        ? <SwapSuggestion>[]
        : todas.where((s) => s.alternative.supermarketCode != unaTienda).toList();
    final swaps = [...enLaMisma, if (_verOtrasTiendas) ...enOtras];

    final totalSaving = swaps.fold<double>(0, (sum, s) => sum + s.savingTotal);
    final over = controller.budgetComparison;
    final gap = over == null ? 0.0 : -over.difference;
    final closesTheGap = totalSaving >= gap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (unaTienda != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              enLaMisma.isEmpty
                  ? 'Tu lista completa está en $unaTiendaNombre y ahí no hay cambios más baratos.'
                  : 'Tu lista completa está en $unaTiendaNombre: estos cambios la mantienen toda ahí.',
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        if (swaps.isNotEmpty)
          Text(
            closesTheGap
                ? 'Con estos cambios podrías ahorrar unos ${formatCop(totalSaving)} y quedar dentro de tu presupuesto.'
                : 'Con estos cambios podrías ahorrar unos ${formatCop(totalSaving)}; aún así te pasarías por '
                    '${formatCop(gap - totalSaving)}.',
            style: AppText.caption,
          ),
        const SizedBox(height: AppSpacing.md),
        for (final swap in swaps) ...[
          _SwapTile(
            swap: swap,
            onApply: () => _apply(context, swap),
            warning: (unaTienda != null && swap.alternative.supermarketCode != unaTienda)
                ? 'Tendrías que ir también a ${swap.alternative.supermarketName}'
                : null,
          ),
          if (swap != swaps.last) const Divider(height: AppSpacing.xl),
        ],
        if (enOtras.isNotEmpty && !_verOtrasTiendas) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() => _verOtrasTiendas = true),
              child: Text('Ver ${enOtras.length} ${enOtras.length == 1 ? 'cambio' : 'cambios'} '
                  'que te llevarían a otra tienda'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
            child: const Text('Listo'),
          ),
        ),
      ],
    );
  }

  Future<void> _apply(BuildContext context, SwapSuggestion swap) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.applySwap(swap);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Cambiamos «${swap.itemName}» por «${swap.alternative.name}».'
            : 'No pudimos hacer el cambio.'),
      ),
    );
  }
}

class _SwapTile extends StatelessWidget {
  final SwapSuggestion swap;
  final VoidCallback onApply;
  final String? warning;

  const _SwapTile({required this.swap, required this.onApply, this.warning});

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
              Text(swap.itemName,
                  style: AppText.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Mejor', style: AppText.caption),
              Text(alt.name,
                  style: AppText.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${formatCop(swap.currentUnitPrice)} → ${formatCop(alt.unitPrice)} · en ${alt.supermarketName}'
                '${swap.quantity > 1 ? ' · x${swap.quantity}' : ''}',
                style: AppText.caption,
              ),
              Text(
                'Ahorras ${formatCop(swap.savingTotal)}',
                style: AppText.caption.copyWith(
                    color: AppColors.success, fontWeight: FontWeight.w700),
              ),
              if (warning != null)
                Text(warning!, style: AppText.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(onPressed: onApply, child: const Text('Cambiar')),
      ],
    );
  }
}
