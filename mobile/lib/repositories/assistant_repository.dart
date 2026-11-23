import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/api_config.dart';
import '../core/api_exception.dart';

/// Conversación con el agente ConveniaBot (n8n). Cada instancia es una conversación:
/// el identificador de sesión hace que el agente recuerde lo que se dijo antes.
class AssistantRepository {
  final http.Client _client;
  final Uri _url;
  final Duration _timeout;
  final String sessionId;

  AssistantRepository({http.Client? client, String? url, Duration? timeout, String? sessionId})
      : _client = client ?? http.Client(),
        _url = Uri.parse(url ?? ApiConfig.assistantUrl),
        _timeout = timeout ?? ApiConfig.assistantTimeout,
        sessionId = sessionId ?? const Uuid().v4();

  /// Envía un mensaje y devuelve la respuesta del agente.
  /// Lanza [ApiException] si el agente no está disponible; la pantalla lo muestra sin detalles técnicos.
  Future<String> ask(String message) async {
    try {
      final response = await _client
          .post(
            _url,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'action': 'sendMessage', 'sessionId': sessionId, 'chatInput': message}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw const ApiException('El asistente no está disponible.');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final output = decoded is Map ? (decoded['output'] ?? decoded['text']) : null;
      if (output is! String || output.trim().isEmpty) {
        throw const ApiException('El asistente respondió vacío.');
      }
      return output.trim();
    } on TimeoutException {
      throw const ApiException('El asistente tardó demasiado en responder.');
    } on SocketException {
      throw const ApiException('No se pudo conectar con el asistente.');
    } on http.ClientException {
      throw const ApiException('No se pudo conectar con el asistente.');
    } on FormatException {
      throw const ApiException('El asistente respondió algo inesperado.');
    }
  }
}
