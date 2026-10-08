import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/auth_controller.dart';
import '../state/shopping_lists_controller.dart';
import '../state/view_status.dart';
import '../models/shopping_list.dart';
import '../widgets/app_sheets.dart';
import '../widgets/create_list_sheet.dart';
import '../widgets/state_views.dart';
import 'shopping_list_detail_screen.dart';

class ShoppingListsScreen extends StatelessWidget {
  const ShoppingListsScreen({super.key});

  /// Al cambiar, Mis listas se recarga (lo dispara la barra de pestañas).
  static final ValueNotifier<int> refreshSignal = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProxyProvider<AuthController, ShoppingListsController>(
      create: (context) => ShoppingListsController(
        accountId: context.read<AuthController>().currentUser?.id,
        refreshSignal: refreshSignal,
      ),
      update: (_, auth, controller) => controller!..onAccountChanged(auth.currentUser?.id),
      child: Scaffold(
        appBar: AppBar(title: const _ListsTitle()),
        floatingActionButton: const _CreateListButton(),
        body: const SafeArea(child: _ListsBody()),
      ),
    );
  }
}

/// "Mis listas" con la cantidad de listas en una insignia, en vez de un rótulo
/// suelto encima de la lista.
class _ListsTitle extends StatelessWidget {
  const _ListsTitle();

  @override
  Widget build(BuildContext context) {
    final count = context.watch<ShoppingListsController>().lists.length;
    return Row(
      children: [
        Text('Mis listas', style: AppText.screenTitle),
        if (count > 0) ...[
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.lavenderMist,
              borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandIndigo),
            ),
          ),
        ],
      ],
    );
  }
}

class _CreateListButton extends StatelessWidget {
  const _CreateListButton();

  Future<void> _showCreateDialog(BuildContext context) async {
    final controller = context.read<ShoppingListsController>();
    final name = await showCreateListSheet(context);

    if (name == null || name.isEmpty || !context.mounted) return;

    final listId = await controller.createList(name);
    if (listId != null && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final summary = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: listId)),
      );
      // Al volver, la lista ya tiene productos y presupuesto: se recarga sin que haya
      // que arrastrar la pantalla.
      await controller.refresh();
      if (summary != null) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.successBorder),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(summary)),
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showCreateDialog(context),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Nueva lista'),
    );
  }
}

class _ListsBody extends StatelessWidget {
  const _ListsBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShoppingListsController>();

    switch (controller.status) {
      case ViewStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ViewStatus.error:
        return ErrorResultsView(onRetry: controller.retry);
      case ViewStatus.empty:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(color: AppColors.lavenderMist, shape: BoxShape.circle),
                  child: const Icon(Icons.shopping_basket_outlined, size: 40, color: AppColors.brandIndigo),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Todavía no tienes listas', style: AppText.screenTitle, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Crea una lista y te decimos en qué supermercado te sale más barata. '
                  'Puedes armarla con un presupuesto.',
                  style: AppText.body,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      case ViewStatus.loaded:
        final lists = controller.lists;
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.horizontalPage,
              AppSpacing.sm,
              AppSpacing.horizontalPage,
              AppSpacing.xxxl * 2,
            ),
            itemCount: lists.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final list = lists[index];
              return ShoppingListCard(
                list: list,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final summary = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: list.id)),
                  );
                  // Al volver, el conteo de productos puede haber cambiado.
                  if (context.mounted) context.read<ShoppingListsController>().refresh();
                  // "Listo" deja un cierre con el resultado (dónde comprar y cuánto).
                  if (summary != null) {
                    messenger.showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 5),
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.successBorder),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: Text(summary)),
                          ],
                        ),
                      ),
                    );
                  }
                },
                onLongPress: () async {
                  final controller = context.read<ShoppingListsController>();
                  final confirmed = await showConfirmSheet(
                    context,
                    title: '¿Eliminar "${list.name}"?',
                    message: list.itemsCount == 0
                        ? 'La lista está vacía. Esta acción no se puede deshacer.'
                        : 'Se borran la lista y sus ${list.itemsCount} '
                            '${list.itemsCount == 1 ? 'producto' : 'productos'}. Esta acción no se puede deshacer.',
                  );
                  if (confirmed) await controller.deleteList(list.id);
                },
              );
            },
          ),
        );
    }
  }
}

/// Tarjeta de una lista: cuántos productos tiene, cuándo se tocó por última
/// vez y su presupuesto, si lo definió.
class ShoppingListCard extends StatelessWidget {
  final ShoppingListSummary list;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ShoppingListCard({super.key, required this.list, required this.onTap, this.onLongPress});

  static String _ago(DateTime utc) {
    final diff = DateTime.now().difference(utc.toLocal());
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'hace ${diff.inDays} ${diff.inDays == 1 ? 'día' : 'días'}';
    final d = utc.toLocal();
    return 'el ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final empty = list.itemsCount == 0;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.mist),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: empty ? AppColors.mist : AppColors.lavenderMist,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                empty ? Icons.playlist_add_rounded : Icons.shopping_basket_outlined,
                color: empty ? AppColors.inkFaint : AppColors.brandIndigo,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(list.name, style: AppText.productName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    empty
                        ? 'Vacía · toca para agregar productos'
                        : '${list.itemsCount} producto${list.itemsCount == 1 ? '' : 's'} · ${_ago(list.updatedAt)}',
                    style: AppText.caption.copyWith(color: empty ? AppColors.warning : AppColors.inkMuted),
                  ),
                  if (list.budget != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.lavenderMist,
                        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                      ),
                      child: Text(
                        'Presupuesto ${formatCop(list.budget!)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brandIndigo),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
