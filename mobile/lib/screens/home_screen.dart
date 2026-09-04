import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/convenia_logo.dart';
import '../widgets/primary_search_field.dart';
import '../widgets/quick_search_chip.dart';
import 'results_screen.dart';

const _quickSearches = ['Leche', 'Arroz', 'Café', 'Huevos'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String term) {
    final query = term.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResultsScreen(query: query)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.horizontalPage,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ConveniaWordmark(),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Antes de comprar, elige dónde.',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AppColors.slate600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _SupermarketVsIndicator(),
              const SizedBox(height: AppSpacing.xxxl),
              const Text('Encuentra dónde te conviene comprar', style: AppText.hero),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Compara precios de supermercados antes de comprar y ahorra en cada producto.',
                style: AppText.body,
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimarySearchField(controller: _searchController, onSubmitted: _search),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () => _search(_searchController.text),
                child: const Text('Buscar'),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Ejemplo: leche, arroz, café, huevos...',
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.xxxl),
              const Text(
                'BÚSQUEDAS FRECUENTES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate400,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _quickSearches
                    .map((term) => QuickSearchChip(label: term, onTap: () => _search(term)))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupermarketVsIndicator extends StatelessWidget {
  const _SupermarketVsIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(AppColors.d1),
        const SizedBox(width: AppSpacing.xs),
        const Text('D1', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text('vs', style: TextStyle(fontSize: 12, color: AppColors.slate400)),
        ),
        _dot(AppColors.exito),
        const SizedBox(width: AppSpacing.xs),
        const Text('Éxito', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
