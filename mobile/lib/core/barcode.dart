/// Limpia un código de barras leído por la cámara o escrito a mano.
///
/// Devuelve solo los dígitos si el largo corresponde a un EAN-8, UPC-12, EAN-13
/// o GTIN-14; si no, null. La validación completa (dígito verificador) la
/// hace la API; aquí solo se evita una consulta con algo que no es un código.
String? cleanBarcode(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  const validLengths = {8, 12, 13, 14};
  return validLengths.contains(digits.length) ? digits : null;
}
