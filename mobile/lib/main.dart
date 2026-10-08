import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/root_shell.dart';
import 'state/auth_controller.dart';
import 'state/coverage_controller.dart';
import 'state/preferences_controller.dart';

void main() {
  runApp(const ConveniaApp());
}

class ConveniaApp extends StatelessWidget {
  const ConveniaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Sesión y preferencias de toda la app -- se crean una sola vez, no por
      // pantalla, para que iniciar sesión o cambiar una preferencia en Perfil
      // se refleje en cualquier otra parte sin recargarla.
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProvider(create: (_) => PreferencesController()),
        // La cobertura sigue a la distancia máxima elegida en Perfil.
        // `lazy: false`: debe existir desde el arranque porque es quien le pone el
        // alcance (`?supermarkets=`) a TODA consulta de precios. Si se crea la
        // primera vez que un widget lo lee, las primeras consultas salen sin
        // filtro y muestran supermercados fuera del alcance.
        ChangeNotifierProxyProvider<PreferencesController, CoverageController>(
          lazy: false,
          create: (_) => CoverageController(),
          update: (_, prefs, coverage) => coverage!
            ..configure(radiusKm: prefs.maxDistanceKm, manual: prefs.manualLocation, eager: false),
        ),
      ],
      child: MaterialApp(
        title: 'Convenia',
        debugShowCheckedModeBanner: false,
        theme: buildConveniaTheme(),
        home: const RootShell(),
      ),
    );
  }
}
