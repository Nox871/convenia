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
    this.hintText = '¿Qué producto estás buscando?',
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
        style: AppText.body.copyWith(color: AppColors.brandDark, fontSize: 15),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: AppColors.slate400, fontSize: 15),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.slate400),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.slate400),
                onPressed: () => controller.clear(),
              );
            },
          ),
        ),
      ),
    );
  }
}
