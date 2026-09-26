/// Espejo de `app.schemas.auth.UserPublic`/`TokenResponse`.
class AuthUser {
  final int id;
  final String email;
  final String role;
  final String? name;

  const AuthUser({required this.id, required this.email, this.role = 'user', this.name});

  bool get isAdmin => role == 'admin';

  bool get hasName => name != null && name!.trim().isNotEmpty;

  /// Nombre completo para mostrar. Si la cuenta aún no tiene nombre (cuentas
  /// anteriores), se usa la parte local del correo como último recurso.
  String get displayName {
    if (hasName) return name!.trim();
    final local = email.split('@').first;
    return local.isEmpty ? email : local[0].toUpperCase() + local.substring(1);
  }

  /// Primer nombre, para el saludo ("Buenas tardes, Andrés").
  String get firstName => displayName.split(RegExp(r'\s+')).first;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      email: json['email'] as String,
      role: json['role'] as String? ?? 'user',
      name: json['name'] as String?,
    );
  }
}

class AuthSession {
  final String accessToken;
  final AuthUser user;

  const AuthSession({required this.accessToken, required this.user});

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
