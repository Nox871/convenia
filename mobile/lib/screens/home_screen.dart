import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../repositories/category_repository.dart';
import '../state/auth_controller.dart';
import '../widgets/convenia_logo.dart';
import '../widgets/primary_search_field.dart';
import '../widgets/quick_search_chip.dart';
import 'results_screen.dart';

const _quickSearches = ['Leche', 'Arroz', 'Café', 'Huevos'];

/// Íconos por etiqueta de categoría (ver `ETIQUETAS_AMIGABLES` en
/// `shared/category_filter.py`) -- puramente decorativo, así que una
/// etiqueta nueva que no esté aquí simplemente cae en el ícono genérico en
/// vez de romper la pantalla.
const _categoryIcons = <String, IconData>{
  'Despensa': Icons.kitchen_outlined,
  'Panadería y desayuno': Icons.bakery_dining_outlined,
  'Bebidas': Icons.local_drink_outlined,
  'Lácteos y huevos': Icons.egg_outlined,
  'Carnes y embutidos': Icons.set_meal_outlined,
  'Congelados': Icons.ac_unit_outlined,
  'Frutas y verduras': Icons.eco_outlined,
  'Snacks': Icons.cookie_outlined,
  'Aseo y cuidado personal': Icons.cleaning_services_outlined,
};

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Buenos días';
  if (hour < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _categoryRepository = CategoryRepository();
  List<Category>? _categories;
  bool _categoriesFailed = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  /// Las categorías son de acceso rápido: si fallan, la búsqueda normal sigue
  /// funcionando, pero NO se esconde la sección en silencio -- se reintenta
  /// una vez sola y, si sigue fallando, se ofrece un botón para reintentar.
  Future<void> _loadCategories({bool retryOnce = true}) async {
    if (mounted) {
      setState(() {
        _categories = null;
        _categoriesFailed = false;
      });
    }
    try {
      final items = await _categoryRepository.listCategories();
      if (mounted) setState(() => _categories = items);
    } catch (_) {
      if (retryOnce) {
        _retryTimer = Timer(const Duration(seconds: 2), () => _loadCategories(retryOnce: false));
      } else if (mounted) {
        setState(() {
          _categories = [];
          _categoriesFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
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

  void _openCategory(String label) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResultsScreen(category: label)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final greetedName = auth.status == AuthStatus.loggedIn
        ? auth.currentUser!.firstName
        : null;

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
              Text(
                greetedName != null ? '${_greeting()}, $greetedName' : _greeting(),
                style: AppText.hero,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                greetedName != null
                    ? '¿Qué vamos a buscar hoy?'
                    : 'Compara precios de supermercados antes de comprar y ahorra en cada producto.',
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
              if (_categories == null || _categories!.isNotEmpty || _categoriesFailed) ...[
                const SizedBox(height: AppSpacing.xxxl),
                const Text(
                  'CATEGORÍAS DE COMPRA',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkFaint,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_categoriesFailed)
                  Row(
                    children: [
                      Expanded(
                        child: Text('No pudimos cargar las categorías.', style: AppText.body),
                      ),
                      TextButton(onPressed: _loadCategories, child: const Text('Reintentar')),
                    ],
                  )
                else
                  _CategoriesGrid(categories: _categories, onTap: _openCategory),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoriesGrid extends StatelessWidget {
  final List<Category>? categories;
  final ValueChanged<String> onTap;

  const _CategoriesGrid({required this.categories, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (categories == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories!.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, index) {
        final category = categories![index];
        return _CategoryCard(category: category, onTap: () => onTap(category.label));
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  const _CategoryCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.mist),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _categoryIcons[category.label] ?? Icons.shopping_basket_outlined,
              color: AppColors.brandIndigo,
              size: 26,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              category.label,
              style: AppText.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${category.supermarkets.length} supermercados',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
