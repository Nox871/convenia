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
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              Text('Encuentra dónde te conviene comprar', style: AppText.hero),
              const SizedBox(height: AppSpacing.sm),
              Text(
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
              Text(
                'Ejemplo: leche, arroz, café, huevos...',
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.xxxl),
              const Text(
                'BÚSQUEDAS FRECUENTES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkFaint,
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
