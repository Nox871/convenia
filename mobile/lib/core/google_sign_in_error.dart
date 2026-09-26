import 'package:flutter/services.dart';

/// Qué le pasó al inicio de sesión con Google, en términos de qué hacer.
enum GoogleSignInProblem {
  /// La persona cerró el selector de cuentas: no es un error.
  canceled,

  /// El teléfono no tiene servicios de Google (típico de Huawei posteriores a
  /// 2019), o están desactivados o desactualizados.
  noGoogleServices,

  /// El SHA-1 o el paquete de esta versión de la app no coinciden con los
  /// registrados en Google Cloud (código 10).
  appNotRegistered,

  /// Pantalla de consentimiento en modo "Prueba" sin esta cuenta como
  /// usuario de prueba, o Google Play Services desactualizado (código 12500).
  consentOrPlayServices,

  network,
  unknown,
}

class GoogleSignInDiagnosis {
  final GoogleSignInProblem problem;

  /// Código numérico de Google (ej. 10), si el error trae uno.
  final int? statusCode;

  const GoogleSignInDiagnosis(this.problem, this.statusCode);

  /// Mensaje para la persona; `null` si simplemente canceló.
  String? get message {
    final code = statusCode == null ? '' : ' (código $statusCode)';
    switch (problem) {
      case GoogleSignInProblem.canceled:
        return null;
      case GoogleSignInProblem.noGoogleServices:
        return 'Este teléfono no tiene los servicios de Google disponibles (o están desactivados o '
            'desactualizados)$code. Puedes iniciar sesión con tu correo y contraseña.';
      case GoogleSignInProblem.appNotRegistered:
        return 'Esta versión de la app no está registrada para iniciar sesión con Google$code. '
            'Usa tu correo y contraseña mientras se corrige.';
      case GoogleSignInProblem.consentOrPlayServices:
        return 'Google rechazó el inicio de sesión$code. Puede que esta cuenta aún no esté autorizada '
            'para probar la app, o que Google Play Services esté desactualizado.';
      case GoogleSignInProblem.network:
        return 'No hay conexión con Google. Revisa tu internet e inténtalo de nuevo.';
      case GoogleSignInProblem.unknown:
        return 'No se pudo iniciar sesión con Google$code. Intenta de nuevo o usa tu correo y contraseña.';
    }
  }
}

/// Códigos de `ApiException` de Google Play Services que importan aquí.
const _serviceProblemCodes = {1, 2, 3, 9, 16, 17}; // faltan, desactualizados, desactivados, no conectado
const _canceledCodes = {12501};
const _networkCodes = {7, 15}; // NETWORK_ERROR, TIMEOUT
const _consentCodes = {12500, 12502};

/// Interpreta la excepción de `GoogleSignIn.signIn()`. El plugin entrega una
/// [PlatformException] cuyo mensaje incluye "ApiException: <código>".
GoogleSignInDiagnosis diagnoseGoogleSignInError(Object error) {
  final text = error is PlatformException
      ? '${error.code} ${error.message ?? ''} ${error.details ?? ''}'
      : error.toString();

  if (error is PlatformException) {
    if (error.code == 'network_error') return const GoogleSignInDiagnosis(GoogleSignInProblem.network, null);
    if (error.code == 'sign_in_canceled') return const GoogleSignInDiagnosis(GoogleSignInProblem.canceled, null);
  }

  final match = RegExp(r'ApiException:\s*(\d+)').firstMatch(text);
  final code = match == null ? null : int.tryParse(match.group(1)!);

  if (code == null) return const GoogleSignInDiagnosis(GoogleSignInProblem.unknown, null);
  if (_canceledCodes.contains(code)) return GoogleSignInDiagnosis(GoogleSignInProblem.canceled, code);
  if (_networkCodes.contains(code)) return GoogleSignInDiagnosis(GoogleSignInProblem.network, code);
  if (code == 10) return GoogleSignInDiagnosis(GoogleSignInProblem.appNotRegistered, code);
  if (_consentCodes.contains(code)) return GoogleSignInDiagnosis(GoogleSignInProblem.consentOrPlayServices, code);
  if (_serviceProblemCodes.contains(code)) return GoogleSignInDiagnosis(GoogleSignInProblem.noGoogleServices, code);
  return GoogleSignInDiagnosis(GoogleSignInProblem.unknown, code);
}
