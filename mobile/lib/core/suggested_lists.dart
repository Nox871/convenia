/// Lista de compras armada de antemano con términos cotidianos. Cada término
/// pasa por la misma búsqueda y revisión que lo que la persona escribe: la app
/// propone un producto real del catálogo y nada se agrega sin confirmar.
class SuggestedList {
  final String name;
  final String description;
  final List<String> terms;

  const SuggestedList(this.name, this.description, this.terms);

  String get asText => terms.join(', ');
}

const suggestedLists = <SuggestedList>[
  SuggestedList('Desayuno básico', 'Lo esencial para arrancar el día',
      ['pan', 'huevos', 'leche', 'café', 'mantequilla', 'queso', 'jugo', 'cereal']),
  SuggestedList('Almuerzo casero', 'Ingredientes de una comida en casa',
      ['arroz', 'pollo', 'papa', 'zanahoria', 'cebolla', 'tomate', 'aceite', 'lentejas']),
  SuggestedList('Despensa básica', 'Productos no perecederos de uso diario',
      ['arroz', 'azúcar', 'sal', 'aceite', 'espagueti', 'frijoles', 'harina', 'atún']),
  SuggestedList('Aseo del hogar', 'Limpieza de la casa y la ropa',
      ['detergente', 'lavaloza', 'límpido', 'suavizante', 'papel higiénico', 'esponja', 'desinfectante']),
  SuggestedList('Onces y bebidas', 'Para picar y tomar',
      ['galletas', 'gaseosa', 'agua', 'yogur', 'chocolate', 'papas fritas']),
  SuggestedList('Lácteos y proteínas', 'Proteína y lácteos de la semana',
      ['leche', 'queso', 'yogur', 'huevos', 'pollo', 'carne molida', 'jamón']),
  SuggestedList('Lonchera escolar', 'Para armar la lonchera',
      ['pan', 'jamón', 'queso', 'jugo', 'galletas', 'yogur', 'manzana']),
];
