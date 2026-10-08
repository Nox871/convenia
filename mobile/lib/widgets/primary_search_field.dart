import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Buscador principal (56px de alto) con ícono de lupa y `onSubmit` al
/// presionar Enter/Buscar en el teclado.
class PrimarySearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSubmitted;
  final FocusNode? focusNode;

  const PrimarySearchField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.hintText = '¿Qué producto buscas?',
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.searchBarHeight,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        style: AppText.body.copyWith(color: AppColors.ink, fontSize: 15),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 15),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkFaint),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.trim().isEmpty) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.close_rounded, color: AppColors.inkFaint),
                    onPressed: () => controller.clear(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: IconButton.filled(
                      tooltip: 'Buscar',
                      style: IconButton.styleFrom(backgroundColor: AppColors.brandIndigo),
                      icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.white, size: 20),
                      onPressed: () => onSubmitted(controller.text),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
