import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../core/api_exception.dart';

/// Capa mínima de acceso HTTP al backend REST de Convenia.
///
/// Es la ÚNICA parte de la app que sabe hablar HTTP. No se usa directamente
/// desde widgets: los repositories la envuelven y exponen métodos de
/// dominio. Nunca hay una conexión a PostgreSQL desde el cliente móvil.
class ApiClient {
  final http.Client _http;

  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  /// Token de sesión (JWT) del usuario que inició sesión, compartido por
  /// todas las instancias de [ApiClient] -- lo actualiza `AuthController`
  /// al iniciar/cerrar sesión. `null` cuando nadie ha iniciado sesión (la
  /// app sigue funcionando igual, sin historial ligado a una cuenta).
  static String? authToken;

  /// Devuelve los códigos de supermercado al alcance de la persona (los que
  /// tienen una tienda dentro de su rango), o `null` si no se puede saber
  /// (sin ubicación) y entonces no se filtra nada. Lo registra
  /// `CoverageController`; se consulta de forma perezosa, sólo cuando una
  /// petición de precios lo necesita, para no hacer red al arrancar.
  static Future<List<String>?> Function()? scopeResolver;

  /// Rutas que muestran precios por supermercado y, por eso, se limitan a
  /// los supermercados al alcance.
  static bool _isScoped(String path) =>
      path.startsWith('/api/v1/products') ||
      path.startsWith('/api/v1/categories') || RegExp(r'^/api/v1/lists/\d+/(cost|savings|single-store)').hasMatch(path);

  Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json'};
    final token = authToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Uri _buildUri(String path, Map<String, String>? queryParameters) {
    return Uri.parse('${ApiConfig.baseUrl}$path').replace(
      queryParameters: queryParameters?.isEmpty == true ? null : queryParameters,
    );
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(ApiConfig.requestTimeout);
    } on TimeoutException {
      throw const ApiException('Tiempo de espera agotado al contactar el servidor.');
    } on SocketException {
      throw const ApiException('No se pudo conectar con el servidor.');
    } on http.ClientException {
      throw const ApiException('No se pudo conectar con el servidor.');
    }
  }

  /// Mensaje de error del backend (campo `detail`), cuando existe -- útil
  /// para errores que el usuario puede entender y corregir (correo ya
  /// registrado, contraseña incorrecta), a diferencia de una falla interna
  /// genérica que nunca debe exponerse tal cual.
  String? _detailOrNull(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] is String) return body['detail'] as String;
    } catch (_) {
      // Cuerpo no es JSON o no tiene `detail` -- se usa el mensaje genérico.
    }
    return null;
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode == 404) {
      throw const NotFoundException('Recurso no encontrado.');
    }
    if (response.statusCode == 401) {
      throw UnauthorizedException(_detailOrNull(response) ?? 'No autorizado.');
    }
    if (response.statusCode == 400 || response.statusCode == 409) {
      final detail = _detailOrNull(response);
      if (detail != null) throw ApiException(detail);
    }
    if (response.statusCode >= 400) {
      throw ApiException('El servidor respondió con un error (${response.statusCode}).');
    }
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw const ApiException('Respuesta inválida del servidor.');
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    var params = queryParameters;
    final resolver = scopeResolver;
    if (resolver != null && _isScoped(path)) {
      final codes = await resolver();
      if (codes != null) params = {...?queryParameters, 'supermarkets': codes.join(',')};
    }
    final uri = _buildUri(path, params);
    final response = await _send(() => _http.get(uri, headers: _headers()));
    _checkStatus(response);
    return _decodeJson(response);
  }

  /// Descarga un archivo (por ejemplo un CSV). Espera más que una petición
  /// normal porque el servidor lo va generando; devuelve el contenido y el
  /// nombre sugerido por el servidor.
  Future<({Uint8List bytes, String filename})> getFile(
    String path, {
    Map<String, String>? queryParameters,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final uri = _buildUri(path, queryParameters);
    final http.Response response;
    try {
      response = await _http.get(uri, headers: _headers()).timeout(timeout);
    } on TimeoutException {
      throw const ApiException('El servidor tardó demasiado en preparar el archivo.');
    } on SocketException {
      throw const ApiException('No se pudo conectar con el servidor.');
    } on http.ClientException {
      throw const ApiException('No se pudo conectar con el servidor.');
    }
    _checkStatus(response);
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp('filename="?([^";]+)"?').firstMatch(disposition);
    return (bytes: response.bodyBytes, filename: match?.group(1) ?? 'convenia.csv');
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final response = await _send(
      () => _http.post(uri, headers: _headers(), body: jsonEncode(body ?? {})),
    );
    _checkStatus(response);
    return _decodeJson(response);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final response = await _send(
      () => _http.put(uri, headers: _headers(), body: jsonEncode(body ?? {})),
    );
    _checkStatus(response);
    return _decodeJson(response);
  }

  /// DELETE que devuelve el recurso actualizado (ej. quitar un ítem de una
  /// lista devuelve la lista resultante).
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final response = await _send(() => _http.delete(uri, headers: _headers()));
    _checkStatus(response);
    return _decodeJson(response);
  }

  /// DELETE que devuelve 204 sin cuerpo (ej. eliminar una lista completa).
  Future<void> deleteNoContent(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final response = await _send(() => _http.delete(uri, headers: _headers()));
    _checkStatus(response);
  }

  void close() => _http.close();
}
