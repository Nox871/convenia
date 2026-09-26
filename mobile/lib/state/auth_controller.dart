import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/api_exception.dart';
import '../core/device_id.dart';
import '../core/google_auth_config.dart';
import '../core/google_sign_in_error.dart';
import '../models/auth.dart';
import '../repositories/auth_repository.dart';
import '../repositories/shopping_list_repository.dart';
import '../services/api_client.dart';

enum AuthStatus { loading, loggedOut, loggedIn }

/// Estado de sesión de toda la app -- se crea una sola vez en `main.dart` y
/// vive mientras la app esté abierta, no por pantalla.
///
/// El token se guarda en almacenamiento seguro del dispositivo (cifrado por
/// el sistema operativo, no en `shared_preferences` plano) para que la
/// sesión sobreviva a cerrar y reabrir la app. Usar la app sin iniciar
/// sesión sigue siendo válido -- el historial, en ese caso, queda ligado al
/// dispositivo (`owner_ref`) como hasta ahora, no a una cuenta.
class AuthController extends ChangeNotifier {
  final AuthRepository _repository;
  final FlutterSecureStorage _storage;
  final GoogleSignIn _googleSignIn;

  static const _tokenKey = 'convenia_auth_token';

  AuthController({
    AuthRepository? repository,
    FlutterSecureStorage? storage,
    GoogleSignIn? googleSignIn,
  }) : _repository = repository ?? AuthRepository(),
       _storage = storage ?? const FlutterSecureStorage(),
       _googleSignIn = googleSignIn ??
           GoogleSignIn(
             serverClientId: GoogleAuthConfig.webClientId,
             scopes: const ['email'],
           ) {
    _restoreSession();
  }

  AuthStatus status = AuthStatus.loading;
  AuthUser? currentUser;
  String? errorMessage;

  bool get isAdmin => currentUser?.isAdmin ?? false;

  /// Las listas hechas en este teléfono como invitado pasan a la cuenta, para
  /// que no se pierdan al iniciar sesión y se conserven si cambia de teléfono.
  /// Es idempotente y no es crítico: si falla, no se interrumpe el inicio de
  /// sesión (se reintenta la próxima vez).
  Future<void> _claimDeviceLists() async {
    try {
      await ShoppingListRepository().claimDeviceLists(await DeviceId.get());
    } catch (e) {
      debugPrint('AuthController: no se pudieron pasar las listas a la cuenta: $e');
    }
  }

  Future<void> _restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) {
      status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }

    ApiClient.authToken = token;
    try {
      currentUser = await _repository.me();
      status = AuthStatus.loggedIn;
      await _claimDeviceLists();
    } on ApiException {
      // El token guardado ya no sirve (expiró, o el usuario fue borrado) --
      // se descarta en silencio y la app vuelve a modo sin sesión, en vez
      // de mostrar un error al abrir la app.
      await _storage.delete(key: _tokenKey);
      ApiClient.authToken = null;
      status = AuthStatus.loggedOut;
    }
    notifyListeners();
  }

  Future<bool> register(String email, String password, {required String name}) =>
      _authenticate(() => _repository.register(email, password, name: name));

  /// Cambia el nombre para mostrar. Devuelve `false` (con `errorMessage`)
  /// si el servidor lo rechaza.
  Future<bool> updateName(String name) async {
    errorMessage = null;
    try {
      currentUser = await _repository.updateName(name.trim());
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String email, String password) =>
      _authenticate(() => _repository.login(email, password));

  Future<bool> _authenticate(Future<AuthSession> Function() action) async {
    errorMessage = null;
    try {
      final session = await action();
      await _storage.write(key: _tokenKey, value: session.accessToken);
      ApiClient.authToken = session.accessToken;
      currentUser = session.user;
      status = AuthStatus.loggedIn;
      await _claimDeviceLists();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Abre el selector nativo de cuentas de Google. Devuelve `false` sin
  /// mostrar error si el usuario simplemente cancela -- cancelar no es una
  /// falla, es una decisión válida.
  Future<bool> loginWithGoogle() async {
    errorMessage = null;
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false; // el usuario canceló el selector

      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        errorMessage = 'Google no entregó un token válido. Intenta de nuevo.';
        notifyListeners();
        return false;
      }

      return await _authenticate(() => _repository.loginWithGoogle(idToken));
    } catch (e, st) {
      debugPrint('loginWithGoogle FALLÓ: $e\n$st');
      // Se traduce el código de Google a qué hacer (configuración, consentimiento,
      // sin servicios de Google, sin internet) en vez de mostrar un código crudo.
      final diagnosis = diagnoseGoogleSignInError(e);
      if (diagnosis.problem == GoogleSignInProblem.canceled) return false;
      errorMessage = diagnosis.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    ApiClient.authToken = null;
    currentUser = null;
    status = AuthStatus.loggedOut;
    notifyListeners();
    if (await _googleSignIn.isSignedIn()) await _googleSignIn.signOut();
  }
}
