import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/product_list_item.dart';
import '../repositories/product_repository.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';

/// Pantalla de búsqueda para elegir un producto y agregarlo a una lista de
/// compra. Al tocar un resultado, hace `Navigator.pop` devolviendo su `id`
/// opaco -- no navega a Detalle, porque aquí el objetivo es "elegir", no
/// "comparar".
class PickProductScreen extends StatefulWidget {
  const PickProductScreen({super.key});

  @override
  State<PickProductScreen> createState() => _PickProductScreenState();
}

class _PickProductScreenState extends State<PickProductScreen> {
  final _repository = ProductRepository();
  final _controller = TextEditingController();
  List<ProductListItem>? _results;
  bool _loading = false;
  String? _error;

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _repository.searchProducts(query: trimmed, limit: 30);
      setState(() => _results = response.items);
    } catch (_) {
      setState(() => _error = 'No pudimos buscar productos. Intenta de nuevo.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Agregar producto', style: AppText.screenTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.horizontalPage),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar producto...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: _search,
              ),
            ),
            if (_loading) const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(_error!, style: const TextStyle(color: AppColors.error)),
              ),
            if (_results != null && _results!.isEmpty && !_loading)
              const Expanded(
                child: EmptyResultsView(
                  title: 'Sin resultados',
                  message: 'Prueba con otro término de búsqueda.',
                ),
              ),
            if (_results != null && _results!.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage),
                  itemCount: _results!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = _results![index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ProductImage(imageUrl: item.imageUrl, size: 48),
                      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${item.supermarketName}${item.price != null ? ' · ${formatCop(item.price!)}' : ''}',
                      ),
                      onTap: () => Navigator.of(context).pop(item.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
