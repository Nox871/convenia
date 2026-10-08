/// Un ítem detectado en una frase hablada de lista de compra, antes de
/// buscarlo en el catálogo.
class SpokenListEntry {
  final int quantity;
  final String searchText;

  const SpokenListEntry({required this.quantity, required this.searchText});
}

const _leadIns = [
  'me gustaria comprar',
  'me gustaría comprar',
  'quisiera comprar',
  'quiero comprar',
  'necesito comprar',
  'voy a comprar',
  'tengo que comprar',
  'debo comprar',
  'hay que comprar',
  'me hacen falta',
  'me hace falta',
  'anota',
  'apunta',
  'necesito',
  'quisiera',
  'quiero',
  'comprar',
  'agregar a la lista',
  'agrega a mi lista',
  'agregar',
  'agrega',
];

const _numberWords = {
  'un': 1, 'una': 1, 'uno': 1,
  'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5,
  'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10,
  'once': 11, 'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15,
  'dieciseis': 16, 'dieciséis': 16, 'diecisiete': 17, 'dieciocho': 18,
  'diecinueve': 19, 'veinte': 20,
  'media': 1, 'medio': 1,
};

// Unidades/envases que se mencionan junto a la cantidad pero no forman
// parte del nombre del producto a buscar (ej. "dos BOLSAS DE arroz" -> se
// busca "arroz", no "bolsas de arroz").
const _fillerWords = {
  'de', 'del', 'la', 'el', 'las', 'los',
  'bolsa', 'bolsas', 'paquete', 'paquetes', 'paq',
  'litro', 'litros', 'lt', 'l',
  'kilo', 'kilos', 'kg',
  'gramo', 'gramos', 'gr', 'g',
  'docena', 'docenas',
  'unidad', 'unidades',
  'libra', 'libras',
  'caja', 'cajas',
  'botella', 'botellas',
  'frasco', 'frascos',
  'tarro', 'tarros',
  'rollo', 'rollos',
  'un', 'una',
};

// Nombres de producto muy comunes (sin tildes). Los reconocedores de voz no
// ponen comas: "arroz, leche, huevos" llega como "arroz leche huevos". Cuando
// un segmento trae varios de estos seguidos, se separa antes de cada uno.
const _productHeads = {
  'arroz', 'leche', 'huevos', 'huevo', 'aguacate', 'pan', 'queso', 'yogurt', 'yogur', 'mantequilla',
  'margarina', 'aceite', 'azucar', 'sal', 'harina', 'pasta', 'pastas', 'espagueti', 'fideos', 'frijol',
  'frijoles', 'lenteja', 'lentejas', 'garbanzo', 'garbanzos', 'avena', 'cereal', 'galletas', 'galleta',
  'cafe', 'chocolate', 'panela', 'atun', 'sardinas', 'pollo', 'carne', 'cerdo', 'pescado', 'jamon',
  'salchicha', 'salchichas', 'chorizo', 'tocineta', 'papa', 'papas', 'yuca', 'platano', 'platanos',
  'tomate', 'tomates', 'cebolla', 'ajo', 'zanahoria', 'lechuga', 'pepino', 'limon', 'limones',
  'naranja', 'naranjas', 'manzana', 'manzanas', 'banano', 'bananos', 'mango', 'fresa', 'fresas', 'uva',
  'uvas', 'papaya', 'piña', 'pina', 'mora', 'maracuya', 'gaseosa', 'jugo', 'agua', 'cerveza', 'te',
  'detergente', 'jabon', 'suavizante', 'lavaloza', 'limpiador', 'blanqueador', 'desinfectante',
  'esponja', 'servilletas', 'shampoo', 'desodorante', 'mayonesa', 'mostaza', 'salsa', 'vinagre',
  'gelatina', 'arepas', 'tortillas', 'cebollin', 'cilantro', 'perejil', 'champinones', 'brocoli',
  'espinaca', 'aromatica', 'mermelada', 'bocadillo', 'maiz', 'mani', 'nueces', 'miel',
};

// Palabras tras las cuales lo siguiente es parte del mismo producto
// ("leche DE coco", "arroz CON pollo", "aceite PARA freir").
const _joiners = {'de', 'del', 'con', 'sin', 'para', 'en', 'a', 'al', 'x'};

// Unidades de conteo: "30 und" es una presentación, no otro producto.
const _countUnits = {'und', 'unds', 'ud', 'uds', 'unid', 'unidad', 'unidades'};

const _unitWords = {
  'und', 'unds', 'ud', 'uds', 'unid',
  'ml', 'lt', 'l', 'litro', 'litros', 'kg', 'kilo', 'kilos', 'gr', 'g', 'gramos', 'libra', 'libras',
  'docena', 'docenas', 'unidad', 'unidades', 'bolsa', 'bolsas', 'paquete', 'paquetes', 'caja', 'cajas',
  'botella', 'botellas',
};

bool _isQuantityToken(String word) =>
    RegExp(r'^\d+$').hasMatch(word) || _numberWords.containsKey(_stripAccents(word));

/// Separa un segmento sin comas que trae varios productos seguidos
/// ("arroz leche huevos" -> arroz | leche | huevos; "2 leche 3 huevos" ->
/// 2 leche | 3 huevos). Es conservador: no parte tras "de/con/sin/para/en"
/// y un nombre compuesto que empieza con un producto ("leche entera") queda
/// junto porque "entera" no es un producto.
List<List<String>> _splitRunOn(List<String> words) {
  final groups = <List<String>>[];
  var current = <String>[];

  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final plain = _stripAccents(word);
    final previous = i == 0 ? null : _stripAccents(words[i - 1]);
    final next = i + 1 < words.length ? _stripAccents(words[i + 1]) : null;

    final afterJoiner = previous != null && _joiners.contains(previous);
    final hasProduct = current.any((w) => _productHeads.contains(_stripAccents(w)));
    // "arroz 2 leche": un número que abre un producto nuevo (no el "900" de
    // "leche 900 ml", que va seguido de una unidad).
    final startsQuantity = _isQuantityToken(word) &&
        hasProduct &&
        !afterJoiner &&
        next != null &&
        !_unitWords.contains(next);
    // "arroz leche": un producto conocido tras otro ya completo. Si el grupo
    // actual es sólo una cantidad ("2 leche"), van juntos.
    // "2 leche", "30 unidades huevo": mientras lo anterior sea sólo una cantidad
    // (con su unidad), el producto que llega es el suyo, no uno nuevo.
    final onlyQuantityPrefix = current.isNotEmpty &&
        _isQuantityToken(current.first) &&
        current.skip(1).every((w) => _unitWords.contains(_stripAccents(w)) || _fillerWords.contains(_stripAccents(w)));
    final startsProduct = _productHeads.contains(plain) &&
        current.isNotEmpty &&
        !afterJoiner &&
        !onlyQuantityPrefix;

    if (startsQuantity || startsProduct) {
      groups.add(current);
      current = <String>[];
    }
    current.add(word);
  }
  if (current.isNotEmpty) groups.add(current);
  return groups;
}

String _stripAccents(String text) {
  const from = 'áéíóúÁÉÍÓÚñÑ';
  const to = 'aeiouAEIOUnN';
  var result = text;
  for (var i = 0; i < from.length; i++) {
    result = result.replaceAll(from[i], to[i]);
  }
  return result;
}

/// Convierte una frase conversacional ("me gustaría comprar 12 huevos, un
/// litro de agua y dos bolsas de arroz") en varios ítems candidatos, cada
/// uno con una cantidad (mejor esfuerzo, editable después por el usuario) y
/// un texto de búsqueda limpio.
///
/// Es deliberadamente un parser de REGLAS, no un modelo de lenguaje: separa
/// por comas/"y", reconoce números (dígitos o en palabras) al inicio de
/// cada segmento y descarta palabras de envase/unidad que no ayudan a
/// buscar el producto. Cuando no hay forma de saber la cantidad exacta
/// (ej. "huevos" solo, o el envase real trae más unidades de las
/// mencionadas), se asume 1 y se dejan las palabras completas para que las
/// sugerencias del catálogo y la confirmación del usuario resuelvan la
/// ambigüedad -- nunca se inventa un tamaño de producto.
List<SpokenListEntry> parseSpokenList(String text) {
  var normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) return [];

  for (final leadIn in _leadIns) {
    if (normalized.startsWith(leadIn)) {
      normalized = normalized.substring(leadIn.length).trim();
      break;
    }
  }

  final segments = normalized
      .split(RegExp(r',| y |;|\n|\by tambi[eé]n\b|\btambi[eé]n\b'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final entries = <SpokenListEntry>[];
  final wordGroups = [
    for (final segment in segments)
      ..._splitRunOn(segment.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList()),
  ];
  for (final words in wordGroups) {
    if (words.isEmpty) continue;

    var quantity = 1;
    var startIndex = 0;

    final digitMatch = RegExp(r'^\d+$').hasMatch(words.first);
    final wordNumber = _numberWords[_stripAccents(words.first)];

    // "30 unidades huevo": con 10 o más es una PRESENTACIÓN (un cartón de 30),
    // no 30 compras. Se conserva junto al nombre para que la búsqueda la entienda.
    if (digitMatch &&
        words.length >= 3 &&
        int.parse(words.first) >= 10 &&
        _countUnits.contains(_stripAccents(words[1]))) {
      final rest = words.sublist(2).where((w) => !_fillerWords.contains(_stripAccents(w))).toList();
      if (rest.isNotEmpty) {
        entries.add(SpokenListEntry(quantity: 1, searchText: '${rest.join(' ')} ${words.first} und'));
        continue;
      }
    }

    if (digitMatch) {
      quantity = int.parse(words.first);
      startIndex = 1;
    } else if (wordNumber != null) {
      quantity = wordNumber;
      startIndex = 1;
    }

    final remaining = words
        .sublist(startIndex)
        .where((w) => !_fillerWords.contains(_stripAccents(w)))
        .toList();

    final searchText = remaining.join(' ').trim();
    if (searchText.isEmpty) continue;

    entries.add(SpokenListEntry(quantity: quantity, searchText: searchText));
  }

  return entries;
}
