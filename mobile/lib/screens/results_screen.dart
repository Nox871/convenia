import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/search_controller.dart';
import '../state/view_status.dart';
import '../widgets/scope_note.dart';
import '../widgets/primary_search_field.dart';
import '../widgets/product_card.dart';
import '../widgets/quick_search_chip.dart';
import '../widgets/state_views.dart';
import 'product_detail_screen.dart';

class ResultsScreen extends StatelessWidget {
  final String query;
  final String? category;

  const ResultsScreen({super.key, this.query = '', this.category});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchResultsController(query: query, category: category),
      child: const _ResultsView(),
    );
  }
}

class _ResultsView extends StatefulWidget {
  const _ResultsView();

  @override
  State<_ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<_ResultsView> {
  bool _editingQuery = false;
  late final TextEditingController _editController;
  final _editFocusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final controller = context.read<SearchResultsController>();
    _editController = TextEditingController(text: controller.query);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 200) {
      context.read<SearchResultsController>().loadMore();
    }
  }

  void _openEdit() {
    setState(() => _editingQuery = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _editFocusNode.requestFocus());
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SearchResultsController>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              controller: controller,
              editing: _editingQuery,
              editController: _editController,
              editFocusNode: _editFocusNode,
              onToggleEdit: () {
                if (_editingQuery) {
                  setState(() => _editingQuery = false);
                } else {
                  _openEdit();
                }
              },
              onSubmitQuery: (value) {
                setState(() => _editingQuery = false);
                controller.updateQuery(value);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _SortBar(controller: controller),
            const SizedBox(height: AppSpacing.sm),
            ScopeNote(onChanged: controller.retry),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _Body(
                controller: controller,
                scrollController: _scrollController,
                onSearchAgain: _openEdit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final SearchResultsController controller;
  final bool editing;
  final TextEditingController editController;
  final FocusNode editFocusNode;
  final VoidCallback onToggleEdit;
  final ValueChanged<String> onSubmitQuery;

  const _Header({
    required this.controller,
    required this.editing,
    required this.editController,
    required this.editFocusNode,
    required this.onToggleEdit,
    required this.onSubmitQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
              ),
              Text('Resultados', style: AppText.screenTitle),
              const Spacer(),
              TextButton.icon(
                onPressed: onToggleEdit,
                icon: Icon(editing ? Icons.close_rounded : Icons.edit_outlined, size: 18),
                label: Text(editing ? 'Cerrar' : 'Cambiar búsqueda'),
              ),
            ],
          ),
          if (editing)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: PrimarySearchField(
                controller: editController,
                onSubmitted: onSubmitQuery,
                focusNode: editFocusNode,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm, bottom: AppSpacing.xs),
              child: RichText(
                text: TextSpan(
                  style: AppText.body,
                  children: [
                    TextSpan(text: controller.category != null ? 'Categoría: ' : 'Buscaste: '),
                    TextSpan(
                      text: '"${controller.category ?? controller.query}"',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    TextSpan(text: '  ·  ${controller.total} productos encontrados'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barra de ORDEN (estilo Google Flights): criterios claros y pocos, nunca
/// una lista fija de supermercados. "Más cercano" queda deshabilitado con un
/// tooltip honesto -- el backend todavía no tiene establecimientos físicos
/// reales que respalden ese criterio, y nunca se ofrece un orden que no
/// pueda producir un resultado real.
class _SortBar extends StatelessWidget {
  final SearchResultsController controller;

  const _SortBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPage),
        children: [
          for (final option in ResultsSort.values) ...[
            FilterChoiceChip(
              label: option.label,
              selected: controller.sort == option,
              onTap: () => controller.setSort(option),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Tooltip(
            message: 'Actívalo dando permiso de ubicación y cuando tengamos '
                'establecimientos físicos cerca de ti',
            child: FilterChoiceChip(
              label: 'Más cercano',
              selected: false,
              enabled: false,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final SearchResultsController controller;
  final ScrollController scrollController;
  final VoidCallback onSearchAgain;

  const _Body({
    required this.controller,
    required this.scrollController,
    required this.onSearchAgain,
  });

  @override
  Widget build(BuildContext context) {
    switch (controller.status) {
      case ViewStatus.loading:
        return const ProductListSkeleton();
      case ViewStatus.error:
        return ErrorResultsView(onRetry: controller.retry);
      case ViewStatus.empty:
        return EmptyResultsView(
          onSearchAgain: onSearchAgain,
          onGoBack: () => Navigator.of(context).maybePop(),
        );
      case ViewStatus.loaded:
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.horizontalPage,
            0,
            AppSpacing.horizontalPage,
            AppSpacing.xxl,
          ),
          itemCount: controller.items.length + (controller.hasNext ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            if (index >= controller.items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final item = controller.items[index];
            return ProductCard(
              item: item,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ProductDetailScreen(productId: item.id, productName: item.name),
                ),
              ),
            );
          },
        );
    }
  }
}
