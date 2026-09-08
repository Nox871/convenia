import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  void _checkStatus(http.Response response) {
    if (response.statusCode == 404) {
      throw const NotFoundException('Recurso no encontrado.');
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
    final uri = _buildUri(path, queryParameters);
    final response = await _send(() => _http.get(uri));
    _checkStatus(response);
    return _decodeJson(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final response = await _send(
      () => _http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body ?? {}),
      ),
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
      () => _http.put(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body ?? {}),
      ),
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
    final response = await _send(() => _http.delete(uri));
    _checkStatus(response);
    return _decodeJson(response);
  }

  /// DELETE que devuelve 204 sin cuerpo (ej. eliminar una lista completa).
  Future<void> deleteNoContent(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final response = await _send(() => _http.delete(uri));
    _checkStatus(response);
  }

  void close() => _http.close();
}
