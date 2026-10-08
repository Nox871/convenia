import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../core/formatters.dart';
import '../repositories/category_repository.dart';
import '../repositories/product_repository.dart';
import '../state/auth_controller.dart';
import '../widgets/convenia_logo.dart';
import '../widgets/primary_search_field.dart';
import '../widgets/quick_search_chip.dart';
import '../widgets/scope_note.dart';
import 'results_screen.dart';

/// Mientras todavía no hay suficientes búsquedas reales (o si no se pueden pedir),
/// estas son las sugerencias de arranque.
const _defaultQuickSearches = ['Leche', 'Arroz', 'Café', 'Huevos'];

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
  final _productRepository = ProductRepository();
  List<String> _quickSearches = _defaultQuickSearches;
  List<Category>? _categories;
  bool _categoriesFailed = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadQuickSearches();
  }

  /// Las búsquedas frecuentes salen de lo que de verdad se busca en la app. Con pocas
  /// búsquedas registradas se completan con las de arranque.
  Future<void> _loadQuickSearches() async {
    try {
      final real = await _productRepository.popularSearches(limit: 6);
      if (!mounted || real.isEmpty) return;
      final merged = [...real];
      for (final d in _defaultQuickSearches) {
        if (merged.length >= 4) break;
        if (!merged.any((m) => m.toLowerCase() == d.toLowerCase())) merged.add(d);
      }
      setState(() => _quickSearches = merged);
    } catch (_) {
      // Se quedan las de arranque.
    }
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

    return ScopeReloader(
      // Al cambiar el alcance (distancia o ubicación) los conteos de las categorías cambian.
      onChanged: _loadCategories,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.horizontalPage,
              vertical: AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ConveniaWordmark(),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Antes de comprar, elige dónde.',
                  style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  greetedName != null ? '${_greeting()}, $greetedName' : _greeting(),
                  style: AppText.hero,
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimarySearchField(controller: _searchController, onSubmitted: _search),
                const SizedBox(height: AppSpacing.xl),
                const _SectionLabel('BÚSQUEDAS FRECUENTES'),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: _quickSearches
                      .map((term) => QuickSearchChip(label: term, onTap: () => _search(term)))
                      .toList(),
                ),
                if (_categories == null || _categories!.isNotEmpty || _categoriesFailed) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionLabel('CATEGORÍAS DE COMPRA'),
                  const SizedBox(height: AppSpacing.md),
                  if (_categoriesFailed)
                    Row(
                      children: [
                        Expanded(child: Text('No pudimos cargar las categorías.', style: AppText.body)),
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
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.inkFaint,
        letterSpacing: 0.6,
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
        // Estructura fija (ícono arriba, título en un espacio de 2 líneas, conteo abajo)
        // para que los íconos de todas las tarjetas queden a la misma altura aunque
        // unos títulos ocupen una línea y otros dos.
        child: Column(
          children: [
            const SizedBox(height: 2),
            Icon(
              _categoryIcons[category.label] ?? Icons.shopping_basket_outlined,
              color: AppColors.brandIndigo,
              size: 26,
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: Center(
                child: Text(
                  category.label,
                  style: AppText.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Text(
              '${_thousands(category.productsCount)} productos',
              style: AppText.caption,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}


/// 1873 -> "1.873" (punto de miles, como en los precios).
String _thousands(int n) => formatCop(n).substring(1);
