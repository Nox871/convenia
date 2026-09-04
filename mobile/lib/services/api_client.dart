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

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path').replace(
      queryParameters: queryParameters?.isEmpty == true ? null : queryParameters,
    );

    http.Response response;
    try {
      response = await _http.get(uri).timeout(ApiConfig.requestTimeout);
    } on TimeoutException {
      throw const ApiException('Tiempo de espera agotado al contactar el servidor.');
    } on SocketException {
      throw const ApiException('No se pudo conectar con el servidor.');
    } on http.ClientException {
      throw const ApiException('No se pudo conectar con el servidor.');
    }

    if (response.statusCode == 404) {
      throw const NotFoundException('Producto no encontrado.');
    }
    if (response.statusCode >= 400) {
      throw ApiException('El servidor respondió con un error (${response.statusCode}).');
    }

    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw const ApiException('Respuesta inválida del servidor.');
    }
  }

  void close() => _http.close();
}
