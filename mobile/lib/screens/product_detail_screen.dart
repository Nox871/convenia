import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/product_detail_controller.dart';
import '../state/view_status.dart';
import '../widgets/comparison_banner.dart';
import '../widgets/price_offer_tile.dart';
import '../widgets/add_to_list_sheet.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';
import 'price_history_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  final String productId;
  final String productName;

  const ProductDetailScreen({super.key, required this.productId, required this.productName});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProductDetailController(productId: productId),
      child: Scaffold(
        appBar: AppBar(title: Text('Comparación', style: AppText.screenTitle)),
        body: SafeArea(child: _DetailBody(fallbackName: productName)),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final String fallbackName;

  const _DetailBody({required this.fallbackName});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProductDetailController>();

    switch (controller.status) {
      case ViewStatus.loading:
        return _DetailSkeleton(productName: fallbackName);
      case ViewStatus.error:
        return ErrorResultsView(onRetry: controller.retry);
      case ViewStatus.empty:
        return EmptyResultsView(
          title: 'No encontramos ese producto',
          message: 'Puede que ya no esté disponible.',
          onGoBack: () => Navigator.of(context).maybePop(),
        );
      case ViewStatus.loaded:
        final detail = controller.detail!;
        final comparison = controller.comparison!;
        // Ofertas con dato primero (ordenadas por precio), "Sin datos" al final.
        final sortedOffers = [...comparison.offers]
          ..sort((a, b) {
            if (a.hasData && b.hasData) return a.price!.compareTo(b.price!);
            if (a.hasData) return -1;
            if (b.hasData) return 1;
            return 0;
          });
        final conDatos = sortedOffers.where((o) => o.hasData).length;
        // Nunca "Todas las ofertas": son observaciones de precio, no ofertas
        // comerciales, y el título debe reflejar honestamente cuántas hay.
        final seccionTitulo = conDatos <= 1 ? 'Disponibilidad' : 'Precios registrados';
        // Con 0-1 ofertas reales, mostrar filas "Sin datos" de las demás
        // tiendas no ayuda a decidir (es obvio que un producto de una sola
        // tienda no está en las otras) -- sólo satura la pantalla. Con 2+
        // ofertas reales, sí vale la pena mostrar dónde NO está disponible.
        final offersToShow =
            conDatos <= 1 ? sortedOffers.where((o) => o.hasData).toList() : sortedOffers;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.horizontalPage,
            AppSpacing.md,
            AppSpacing.horizontalPage,
            AppSpacing.xxxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductImage(imageUrl: detail.imageUrl, size: 88),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (detail.brand != null && detail.brand!.isNotEmpty)
                          Text(detail.brand!.toUpperCase(), style: AppText.caption),
                        const SizedBox(height: 2),
                        Text(detail.name, style: AppText.hero.copyWith(fontSize: 18)),
                        if (detail.category != null) ...[
                          const SizedBox(height: 4),
                          Text(detail.category!, style: AppText.body),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              ComparisonBanner(
                offers: comparison.offers,
                bestPrice: comparison.bestPrice,
                isPartial: comparison.isPartial,
                savingsAbsolute: comparison.savingsAbsolute,
                savingsPercentage: comparison.savingsPercentage,
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(seccionTitulo, style: AppText.sectionTitle),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Agregar a lista',
                        icon: const Icon(Icons.playlist_add_rounded),
                        onPressed: () => showAddToListSheet(context, comparison.product.id),
                      ),
                      IconButton(
                        tooltip: 'Ver historial',
                        icon: const Icon(Icons.show_chart_rounded),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PriceHistoryScreen(
                                productId: comparison.product.id,
                                productName: comparison.product.name,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (offersToShow.isEmpty)
                Text('Todavía no tenemos precios registrados.', style: AppText.body)
              else
                ...offersToShow.map(
                  (offer) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: PriceOfferTile(
                      offer: offer,
                      isBest: comparison.bestPrice != null &&
                          offer.supermarketCode == comparison.bestPrice!.supermarketCode,
                    ),
                  ),
                ),
            ],
          ),
        );
    }
  }
}

class _DetailSkeleton extends StatelessWidget {
  final String productName;

  const _DetailSkeleton({required this.productName});

  @override
  Widget build(BuildContext context) {
    Widget bone(double width, double height) => Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.horizontalPage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bone(120, 88),
          const SizedBox(height: AppSpacing.sm),
          Text(
            productName,
            style: AppText.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          bone(double.infinity, 120),
        ],
      ),
    );
  }
}
