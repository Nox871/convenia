import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Hoja para crear una lista: nombre libre o uno de los sugeridos. Devuelve el
/// nombre elegido, o null si se cancela.
Future<String?> showCreateListSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _CreateListSheet(),
  );
}

class _CreateListSheet extends StatefulWidget {
  const _CreateListSheet();

  @override
  State<_CreateListSheet> createState() => _CreateListSheetState();
}

class _CreateListSheetState extends State<_CreateListSheet> {
  static const _ideas = [
    'Mercado semanal',
    'Mercado del mes',
    'Aseo del hogar',
    'Desayunos',
    'Reunión o fiesta',
  ];

  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canCreate => _controller.text.trim().isNotEmpty;

  void _submit() {
    if (_canCreate) Navigator.of(context).pop(_controller.text.trim());
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
                child: const Icon(Icons.shopping_basket_outlined, color: AppColors.brandIndigo),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Nueva lista', style: AppText.screenTitle)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Agrega productos y te decimos en qué supermercado te sale más barato.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Nombre de la lista',
              hintText: 'Ej. Mercado semanal',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('O elige una idea', style: AppText.caption),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final idea in _ideas)
                ActionChip(
                  label: Text(idea),
                  onPressed: () => setState(() {
                    _controller.text = idea;
                    _controller.selection = TextSelection.collapsed(offset: idea.length);
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
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
                  onPressed: _canCreate ? _submit : null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Crear lista'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
