import 'dart:convert';

import 'package:convenia_mobile/core/api_exception.dart';
import 'package:convenia_mobile/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('descarga un archivo con el nombre que sugiere el servidor', () async {
    final client = ApiClient(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/admin/exports/price-history');
        expect(request.url.queryParameters['days'], '30');
        return http.Response.bytes(
          utf8.encode('a;b\r\n1;2\r\n'),
          200,
          headers: {'content-disposition': 'attachment; filename="convenia_historial_todos_2026-09-25.csv"'},
        );
      }),
    );

    final file = await client.getFile('/api/v1/admin/exports/price-history', queryParameters: {'days': '30'});

    expect(file.filename, 'convenia_historial_todos_2026-09-25.csv');
    expect(utf8.decode(file.bytes), 'a;b\r\n1;2\r\n');
  });

  test('sin nombre en la respuesta usa uno por defecto', () async {
    final client = ApiClient(client: MockClient((_) async => http.Response('x', 200)));

    final file = await client.getFile('/api/v1/admin/exports/price-history');

    expect(file.filename, 'convenia.csv');
  });

  test('un error del servidor (por ejemplo, demasiados registros) llega con su mensaje', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'El historial pedido tiene 400,000 registros'}), 400),
      ),
    );

    expect(
      () => client.getFile('/api/v1/admin/exports/price-history'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('400,000'))),
    );
  });

  test('un usuario común (403) no descarga nada', () async {
    final client = ApiClient(client: MockClient((_) async => http.Response('{}', 403)));

    expect(() => client.getFile('/api/v1/admin/exports/price-history'), throwsA(isA<ApiException>()));
  });
}
