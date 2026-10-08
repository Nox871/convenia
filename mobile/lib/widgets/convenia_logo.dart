import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Isotipo de Convenia: el monograma C+V (una C y una V que forman un prisma que
/// apunta hacia abajo: "elige dónde") en blanco sobre un cuadrado oscuro de
/// esquinas redondeadas. Es el mismo diseño del ícono de la app.
class ConveniaMark extends StatelessWidget {
  final double size;

  const ConveniaMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F12),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      padding: EdgeInsets.all(size * 0.2),
      child: Image.asset(
        'assets/logo/convenia_mark_white.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Convenia',
      ),
    );
  }
}

/// Lockup horizontal: isotipo + wordmark "Convenia", para el Home.
class ConveniaWordmark extends StatelessWidget {
  final double markSize;

  const ConveniaWordmark({super.key, this.markSize = 40});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConveniaMark(size: markSize),
        const SizedBox(width: AppSpacing.sm),
        const Text(
          'Convenia',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}
