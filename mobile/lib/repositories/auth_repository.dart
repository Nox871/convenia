import '../models/auth.dart';
import '../services/api_client.dart';

/// Registro e inicio de sesión con correo y contraseña.
class AuthRepository {
  final ApiClient _client;

  AuthRepository({ApiClient? client}) : _client = client ?? ApiClient();

  Future<AuthSession> register(String email, String password, {required String name}) async {
    final json = await _client.postJson(
      '/api/v1/auth/register',
      body: {'email': email, 'password': password, 'name': name, 'accepted_terms': true},
    );
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> login(String email, String password) async {
    final json = await _client.postJson(
      '/api/v1/auth/login',
      body: {'email': email, 'password': password},
    );
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> loginWithGoogle(String idToken) async {
    final json = await _client.postJson('/api/v1/auth/google', body: {'id_token': idToken});
    return AuthSession.fromJson(json);
  }

  Future<AuthUser> updateName(String name) async {
    final json = await _client.putJson('/api/v1/auth/me', body: {'name': name});
    return AuthUser.fromJson(json);
  }

  Future<AuthUser> me() async {
    final json = await _client.getJson('/api/v1/auth/me');
    return AuthUser.fromJson(json);
  }
}
