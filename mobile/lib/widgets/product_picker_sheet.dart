import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../models/product_list_item.dart';
import '../repositories/product_repository.dart';
import 'product_card.dart';
import 'scope_note.dart';

/// Buscador para elegir un producto concreto (por ejemplo, para cambiar el que
/// se propuso). Muestra TODOS los productos que coinciden, no sólo unas pocas
/// sugerencias, ordenados de menor a mayor precio. Devuelve el elegido o null.
Future<ProductListItem?> showProductPicker(BuildContext context, {String initialQuery = ''}) {
  return showModalBottomSheet<ProductListItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.softIvory,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ProductPickerSheet(initialQuery: initialQuery),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  final String initialQuery;

  const _ProductPickerSheet({required this.initialQuery});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  static const _pageSize = 20;

  final _repository = ProductRepository();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<ProductListItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = false;
  bool _failed = false;
  int _page = 1;
  int _total = 0;
  int _generation = 0; // descarta respuestas de una búsqueda ya reemplazada

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await _repository.searchProducts(query: _controller.text, sort: 'price', page: 1, limit: _pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.items);
        _page = r.pagination.page;
        _hasNext = r.pagination.hasNext;
        _total = r.pagination.total;
        _loading = false;
      });
    } on ApiException {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext || _loading) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final r = await _repository.searchProducts(
        query: _controller.text,
        sort: 'price',
        page: _page + 1,
        limit: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(r.items);
        _page = r.pagination.page;
        _hasNext = r.pagination.hasNext;
      });
    } on ApiException {
      // se conserva lo ya cargado
    } finally {
      if (mounted && generation == _generation) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.88;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.horizontalPage, 0, AppSpacing.horizontalPage, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Elige un producto', style: AppText.screenTitle),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _controller,
                    onChanged: _onChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Busca por nombre, marca o presentación',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _controller.clear();
                                _search();
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Busca sólo en las tiendas a tu alcance: se dice cuáles y se puede ampliar.
                  ScopeNote(padded: false, onChanged: _search),
                  if (!_loading && !_failed)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        '$_total ${_total == 1 ? 'producto' : 'productos'} · del más barato al más caro',
                        style: AppText.caption,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.inkFaint),
            const SizedBox(height: AppSpacing.sm),
            const Text('No pudimos buscar. Revisa tu conexión.'),
            TextButton(onPressed: _search, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'No encontramos productos con esa búsqueda en las tiendas a tu alcance. '
            'Prueba con menos palabras o amplía la distancia arriba.',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(AppSpacing.horizontalPage, 0, AppSpacing.horizontalPage, AppSpacing.xxl),
      itemCount: _items.length + (_hasNext ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final item = _items[i];
        return ProductCard(item: item, onTap: () => Navigator.of(context).pop(item));
      },
    );
  }
}
