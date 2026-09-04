/// Configuración de la URL base del backend.
///
/// Se resuelve en tiempo de compilación con `--dart-define`, para no
/// hardcodear una única URL de producción:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///
/// Valores típicos:
/// - Emulador Android: http://10.0.2.2:8000  (10.0.2.2 apunta al host desde el emulador)
/// - Dispositivo físico en la misma red LAN: http://<IP-LAN-DEL-PC>:8000
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const Duration requestTimeout = Duration(seconds: 10);
}
