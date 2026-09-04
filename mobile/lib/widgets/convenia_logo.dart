import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Isotipo de Convenia: caja oscura con esquinas redondeadas que contiene un
/// símbolo de comparación entre dos alternativas — un nodo neutro (la opción
/// que no conviene) y un nodo verde (la opción óptima), unidos por una línea
/// que sugiere "comparar y elegir". No es un ícono genérico de Flutter.
class ConveniaMark extends StatelessWidget {
  final double size;

  const ConveniaMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.brandDark,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      padding: EdgeInsets.all(size * 0.2),
      child: CustomPaint(painter: _CompareSymbolPainter()),
    );
  }
}

class _CompareSymbolPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.slate400.withOpacity(0.9)
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round;

    final neutralPoint = Offset(0, size.height);
    final optimalPoint = Offset(size.width, 0);

    canvas.drawLine(neutralPoint, optimalPoint, linePaint);

    final neutralRadius = size.width * 0.16;
    final optimalRadius = size.width * 0.20;

    canvas.drawCircle(
      neutralPoint,
      neutralRadius,
      Paint()..color = AppColors.slate400,
    );

    canvas.drawCircle(
      optimalPoint,
      optimalRadius,
      Paint()..color = AppColors.bestPriceGreen,
    );
    canvas.drawCircle(
      optimalPoint,
      optimalRadius,
      Paint()
        ..color = AppColors.bestPriceBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.045,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
            color: AppColors.brandDark,
          ),
        ),
      ],
    );
  }
}
