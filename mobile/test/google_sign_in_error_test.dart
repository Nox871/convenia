import 'package:convenia_mobile/core/google_sign_in_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PlatformException _api(int code) => PlatformException(
  code: 'sign_in_failed',
  message: 'com.google.android.gms.common.api.ApiException: $code: ',
);

void main() {
  test('código 10: la app no está registrada (SHA-1 o paquete)', () {
    final d = diagnoseGoogleSignInError(_api(10));

    expect(d.problem, GoogleSignInProblem.appNotRegistered);
    expect(d.statusCode, 10);
    expect(d.message, contains('no está registrada'));
  });

  test('código 12500: consentimiento o Play Services', () {
    final d = diagnoseGoogleSignInError(_api(12500));

    expect(d.problem, GoogleSignInProblem.consentOrPlayServices);
    expect(d.message, contains('12500'));
  });

  test('cancelar no es un error y no muestra mensaje', () {
    expect(diagnoseGoogleSignInError(_api(12501)).problem, GoogleSignInProblem.canceled);
    expect(diagnoseGoogleSignInError(_api(12501)).message, isNull);
    expect(
      diagnoseGoogleSignInError(PlatformException(code: 'sign_in_canceled')).problem,
      GoogleSignInProblem.canceled,
    );
  });

  test('servicios de Google ausentes o desactivados (caso Huawei sin GMS)', () {
    for (final code in [1, 2, 3, 9, 16, 17]) {
      final d = diagnoseGoogleSignInError(_api(code));

      expect(d.problem, GoogleSignInProblem.noGoogleServices, reason: 'código $code');
      expect(d.message, contains('correo y contraseña'));
    }
  });

  test('sin conexión', () {
    expect(diagnoseGoogleSignInError(_api(7)).problem, GoogleSignInProblem.network);
    expect(
      diagnoseGoogleSignInError(PlatformException(code: 'network_error')).problem,
      GoogleSignInProblem.network,
    );
  });

  test('un error sin código de Google es desconocido', () {
    final d = diagnoseGoogleSignInError(StateError('algo raro'));

    expect(d.problem, GoogleSignInProblem.unknown);
    expect(d.statusCode, isNull);
  });
}
