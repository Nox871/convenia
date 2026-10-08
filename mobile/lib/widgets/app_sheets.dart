import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Hojas inferiores que reemplazan a los diálogos: mismo aspecto en toda la
/// app, los botones lado a lado (Cancelar a la izquierda, la acción a la
/// derecha) y el teclado nunca tapa los campos.

Future<T?> _showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: builder,
  );
}

class _SheetFrame extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? subtitle;
  final Widget? body;
  final String confirmLabel;
  final IconData? confirmIcon;
  final VoidCallback? onConfirm;
  final VoidCallback onCancel;
  final bool destructive;

  const _SheetFrame({
    required this.icon,
    required this.title,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.iconColor = AppColors.brandIndigo,
    this.iconBackground = AppColors.lavenderMist,
    this.subtitle,
    this.body,
    this.confirmIcon,
    this.destructive = false,
  });

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
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(title, style: AppText.screenTitle)),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(subtitle!, style: AppText.body),
            ],
            if (body != null) ...[
              const SizedBox(height: AppSpacing.lg),
              body!,
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.buttonHeight)),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: confirmIcon == null ? const SizedBox.shrink() : Icon(confirmIcon, size: 20),
                    label: Text(confirmLabel),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
                      backgroundColor: destructive ? AppColors.error : null,
                      foregroundColor: destructive ? AppColors.white : null,
                    ),
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

/// Pide un texto corto (renombrar, editar nombre...). Devuelve el texto o null.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  String initial = '',
  String label = 'Nombre',
  String? hint,
  String confirmLabel = 'Guardar',
  IconData icon = Icons.edit_outlined,
  int maxLength = 40,
  TextCapitalization capitalization = TextCapitalization.sentences,
}) {
  return _showAppSheet<String>(
    context,
    (_) => _TextSheet(
      title: title,
      subtitle: subtitle,
      initial: initial,
      label: label,
      hint: hint,
      confirmLabel: confirmLabel,
      icon: icon,
      maxLength: maxLength,
      capitalization: capitalization,
    ),
  );
}

class _TextSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String initial;
  final String label;
  final String? hint;
  final String confirmLabel;
  final IconData icon;
  final int maxLength;
  final TextCapitalization capitalization;

  const _TextSheet({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.label,
    required this.hint,
    required this.confirmLabel,
    required this.icon,
    required this.maxLength,
    required this.capitalization,
  });

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _ready => _controller.text.trim().isNotEmpty;

  void _submit() {
    if (_ready) Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      confirmLabel: widget.confirmLabel,
      confirmIcon: Icons.check_rounded,
      onConfirm: _ready ? _submit : null,
      onCancel: () => Navigator.of(context).pop(),
      body: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        textCapitalization: widget.capitalization,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
      ),
    );
  }
}

/// Confirmación de una acción (por ejemplo eliminar). Devuelve true si se confirma.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Eliminar',
  bool destructive = true,
  IconData icon = Icons.delete_outline_rounded,
}) async {
  final result = await _showAppSheet<bool>(
    context,
    (sheetContext) => _SheetFrame(
      icon: icon,
      iconColor: destructive ? AppColors.error : AppColors.brandIndigo,
      iconBackground: destructive ? AppColors.errorSurface : AppColors.lavenderMist,
      title: title,
      subtitle: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      onConfirm: () => Navigator.of(sheetContext).pop(true),
      onCancel: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  return result == true;
}

/// Resultado de [showAmountSheet]: un monto nuevo o quitar el que había.
typedef AmountResult = ({int? value, bool remove});

/// Pide un monto en pesos (por ejemplo el presupuesto de una lista).
Future<AmountResult?> showAmountSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  int? initial,
  bool allowRemove = false,
}) {
  return _showAppSheet<AmountResult>(
    context,
    (_) => _AmountSheet(title: title, subtitle: subtitle, initial: initial, allowRemove: allowRemove),
  );
}

class _AmountSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int? initial;
  final bool allowRemove;

  const _AmountSheet({required this.title, required this.subtitle, required this.initial, required this.allowRemove});

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial?.toString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _value {
    final v = int.tryParse(_controller.text.replaceAll(RegExp(r'[^0-9]'), ''));
    return (v == null || v <= 0) ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      icon: Icons.savings_outlined,
      title: widget.title,
      subtitle: widget.subtitle,
      confirmLabel: 'Guardar',
      confirmIcon: Icons.check_rounded,
      onConfirm: _value == null ? null : () => Navigator.of(context).pop<AmountResult>((value: _value, remove: false)),
      onCancel: () => Navigator.of(context).pop(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Cuánto quieres gastar', prefixText: r'$ '),
          ),
          if (widget.allowRemove)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop<AmountResult>((value: null, remove: true)),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Quitar el presupuesto'),
              ),
            ),
        ],
      ),
    );
  }
}
