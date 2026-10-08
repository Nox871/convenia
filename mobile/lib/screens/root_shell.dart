import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'shopping_lists_screen.dart';
import 'stores_screen.dart';

/// Shell de navegación principal: Inicio, Listas, Tiendas y
/// Perfil son accesos permanentes; Búsqueda/Resultados/Detalle/
/// Comparación/Historial se alcanzan empujando pantallas desde Inicio o
/// Resultados, no como pestañas propias.
///
/// Cada pestaña se construye SOLO la primera vez que se selecciona (no con
/// `IndexedStack`, que montaría las 4 de una y dispararía sus llamadas HTTP
/// de inmediato) — así Inicio sigue siendo la única pantalla sin red al
/// arrancar la app.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final Set<int> _visited = {0};

  static const _tabs = [
    HomeScreen(),
    ShoppingListsScreen(),
    StoresScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    _visited.add(_index);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _visited.contains(i) ? _tabs[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // Listas: al abrir la pestaña se recargan, por si cambió algo en otra pantalla.
          if (i == 1) ShoppingListsScreen.refreshSignal.value++;
        },
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.lavenderMist,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            label: 'Listas',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            label: 'Tiendas',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
