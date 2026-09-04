/// Error de dominio para fallas de red/backend, independiente de `http`.
/// La UI solo necesita saber "no se pudo cargar", nunca el detalle técnico
/// (evita filtrar errores internos del backend, igual que hace la API).
class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

/// Caso especial de [ApiException]: el backend respondió 404. Se distingue
/// del resto de errores porque en la UI no es "algo se rompió" sino
/// "ese producto no existe" (estado empty, no estado error).
class NotFoundException extends ApiException {
  const NotFoundException(super.message);
}
