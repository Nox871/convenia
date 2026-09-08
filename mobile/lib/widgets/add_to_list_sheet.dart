import 'package:flutter/material.dart';

import '../core/device_id.dart';
import '../core/theme.dart';
import '../models/shopping_list.dart';
import '../repositories/shopping_list_repository.dart';

/// Bottom sheet para agregar `productId` a una lista existente o a una
/// nueva. Se usa desde la pantalla de Detalle/Comparación.
Future<void> showAddToListSheet(BuildContext context, String productId) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddToListSheet(productId: productId),
  );
}

class _AddToListSheet extends StatefulWidget {
  final String productId;

  const _AddToListSheet({required this.productId});

  @override
  State<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends State<_AddToListSheet> {
  final _repository = ShoppingListRepository();
  List<ShoppingListSummary>? _lists;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ownerRef = await DeviceId.get();
    try {
      final lists = await _repository.listLists(ownerRef);
      if (mounted) setState(() => _lists = lists);
    } catch (_) {
      if (mounted) setState(() => _lists = []);
    }
  }

  Future<void> _addTo(int listId) async {
    setState(() => _busy = true);
    final ownerRef = await DeviceId.get();
    try {
      await _repository.addItem(listId, ownerRef, widget.productId);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agregado a la lista.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos agregarlo. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndAdd() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva lista'),
        content: TextField(controller: nameController, autofocus: true),
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
    if (name == null || name.isEmpty) return;

    setState(() => _busy = true);
    final ownerRef = await DeviceId.get();
    final created = await _repository.createList(ownerRef, name);
    await _addTo(created.id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Agregar a lista', style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.md),
            if (_lists == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_lists!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('Todavía no tienes listas.', style: AppText.body),
              )
            else
              ..._lists!.map(
                (list) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(list.name),
                  subtitle: Text('${list.itemsCount} productos'),
                  onTap: _busy ? null : () => _addTo(list.id),
                ),
              ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_rounded),
              title: const Text('Crear nueva lista'),
              onTap: _busy ? null : _createAndAdd,
            ),
          ],
        ),
      ),
    );
  }
}
