import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Skeleton simple (sin dependencias externas) para la lista de resultados
/// mientras se consulta el backend.
class ProductListSkeleton extends StatelessWidget {
  final int itemCount;

  const ProductListSkeleton({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.horizontalPage),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.mist),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bone(width: 72, height: 72, radius: 12),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bone(width: 90, height: 10),
                const SizedBox(height: AppSpacing.sm),
                _bone(width: double.infinity, height: 14),
                const SizedBox(height: AppSpacing.sm),
                _bone(width: 120, height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bone({required double width, required double height, double radius = 6}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Estado vacío: "No encontramos ese producto" + acciones de recuperación.
class EmptyResultsView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onSearchAgain;
  final VoidCallback? onGoBack;

  const EmptyResultsView({
    super.key,
    this.title = 'No encontramos ese producto',
    this.message = 'Prueba con otro nombre o revisa cómo lo escribiste.',
    this.onSearchAgain,
    this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.mist,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off_rounded, color: AppColors.inkFaint, size: 32),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: AppText.screenTitle, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (onSearchAgain != null)
              ElevatedButton(onPressed: onSearchAgain, child: const Text('Buscar otro producto')),
            if (onGoBack != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onGoBack, child: const Text('Volver')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de error de red/backend: "No pudimos cargar los resultados".
class ErrorResultsView extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;

  const ErrorResultsView({
    super.key,
    required this.onRetry,
    this.message = 'No pudimos cargar los resultados',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.errorSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 32),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(message, style: AppText.screenTitle, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Verifica tu conexión o intenta nuevamente.',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(onPressed: onRetry, child: const Text('Intentar de nuevo')),
          ],
        ),
      ),
    );
  }
}
