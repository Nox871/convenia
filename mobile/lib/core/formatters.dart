/// Formatea un valor numérico como precio colombiano: sin decimales y con
/// punto como separador de miles, ej. 3800 -> "$3.800".
///
/// Implementado sin `intl` a propósito: es una regla fija de formato (no
/// depende de locale del dispositivo) y evita cargar datos de localización
/// que no se pueden validar en este entorno.
String formatCop(num value) {
  final rounded = value.round();
  final negative = rounded < 0;
  final digits = rounded.abs().toString();

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write('.');
    }
  }

  return '${negative ? '-' : ''}\$${buffer.toString()}';
}

/// Extrae una "presentación" (peso/volumen/unidad) del nombre del producto
/// cuando es reconocible, ej. "Arroz Diana 500 G" -> "500 G".
/// Devuelve null si no se encuentra un patrón razonable — nunca se inventa.
String? extractPresentation(String productName) {
  final pattern = RegExp(
    r'(\d+(?:[.,]\d+)?\s?(?:g|gr|gramos|kg|kilos?|ml|cc|l|lt|litros?|un|und|ud|uds|pulgadas))\b',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(productName);
  return match?.group(1)?.trim();
}
