/// Convierte el texto que devuelve el OCR de una foto de lista en un producto
/// por línea, listo para buscar.
///
/// Las listas escritas o impresas traen cosas que no son el producto: viñetas
/// ("-", "•", "☐"), numeración ("1.", "2)"), precios ("$5.200") y encabezados
/// ("Lista de compras"). Se quitan aquí; lo que queda lo revisa la persona
/// antes de agregar nada, así que ante la duda se conserva la línea.
library;

final _leadingMarkers = RegExp(r'^[\s\-–—•·*○●◦▪■□☐☑✓✔\[\]()>]+');
final _leadingNumbering = RegExp(r'^\d{1,2}\s*[.)\-]\s+');
final _trailingPrice = RegExp(r'\s+\$?\s*\d{1,3}(?:[.,]\d{3})+\s*$|\s+\$\s*\d+\s*$');
final _letters = RegExp(r'[A-Za-zÁÉÍÓÚáéíóúÑñÜü]');
final _headers = {
  'lista',
  'lista de compras',
  'lista de mercado',
  'compras',
  'mercado',
  'supermercado',
  'mi lista',
};

String _plain(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áä]'), 'a')
    .replaceAll(RegExp('[éë]'), 'e')
    .replaceAll(RegExp('[íï]'), 'i')
    .replaceAll(RegExp('[óö]'), 'o')
    .replaceAll(RegExp('[úü]'), 'u')
    .replaceAll(RegExp(r'[:.]+$'), '')
    .trim();

List<String> cleanOcrLines(String text) {
  final result = <String>[];
  for (final raw in text.split('\n')) {
    var line = raw.trim();
    line = line.replaceFirst(_leadingMarkers, '');
    line = line.replaceFirst(_leadingNumbering, '');
    line = line.replaceFirst(_trailingPrice, '');
    line = line.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Debe tener al menos 3 letras (descarta "12", "$", "-", ruido suelto).
    if (_letters.allMatches(line).length < 3) continue;
    if (_headers.contains(_plain(line))) continue;
    result.add(line);
  }
  return result;
}
