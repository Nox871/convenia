import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ConveniaApp());
}

class ConveniaApp extends StatelessWidget {
  const ConveniaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Convenia',
      debugShowCheckedModeBanner: false,
      theme: buildConveniaTheme(),
      home: const HomeScreen(),
    );
  }
}
