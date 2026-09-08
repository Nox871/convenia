import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/shopping_lists_controller.dart';
import '../state/view_status.dart';
import '../widgets/state_views.dart';
import 'shopping_list_detail_screen.dart';

/// Pantalla "Listas" (ERS §16/§23.6).
class ShoppingListsScreen extends StatelessWidget {
  const ShoppingListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ShoppingListsController(),
      child: Scaffold(
        appBar: AppBar(title: Text('Mis listas', style: AppText.screenTitle)),
        floatingActionButton: const _CreateListButton(),
        body: const SafeArea(child: _ListsBody()),
      ),
    );
  }
}

class _CreateListButton extends StatelessWidget {
  const _CreateListButton();

  Future<void> _showCreateDialog(BuildContext context) async {
    final controller = context.read<ShoppingListsController>();
    final nameController = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva lista'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ej. Mercado semanal'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(nameController.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !context.mounted) return;

    final listId = await controller.createList(name);
    if (listId != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: listId)),
      );
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
        return const EmptyResultsView(
          title: 'Todavía no tienes listas',
          message: 'Crea una lista para comparar su costo entre supermercados.',
        );
      case ViewStatus.loaded:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.horizontalPage,
            AppSpacing.md,
            AppSpacing.horizontalPage,
            AppSpacing.xxxl * 2,
          ),
          itemCount: controller.lists.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final list = controller.lists[index];
            return Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                border: Border.all(color: AppColors.mist),
              ),
              child: ListTile(
                title: Text(list.name, style: AppText.productName),
                subtitle: Text(
                  '${list.itemsCount} producto${list.itemsCount == 1 ? '' : 's'}',
                  style: AppText.caption,
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: list.id)),
                ),
              ),
            );
          },
        );
    }
  }
}
