import 'dart:convert';

import 'package:convenia_mobile/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<Uri> requested;
  late ApiClient client;

  setUp(() {
    requested = [];
    client = ApiClient(
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );
  });

  tearDown(() => ApiClient.scopeResolver = null);

  test('el costo de una lista se limita a los supermercados al alcance', () async {
    ApiClient.scopeResolver = () async => ['D1', 'EXITO'];

    await client.getJson('/api/v1/lists/4/cost', queryParameters: {'owner_ref': 'x'});
    await client.getJson('/api/v1/lists/4/cost/distributed', queryParameters: {'owner_ref': 'x'});
    await client.getJson('/api/v1/lists/4/savings', queryParameters: {'owner_ref': 'x'});

    expect(requested[0].queryParameters['supermarkets'], 'D1,EXITO');
    expect(requested[1].queryParameters['supermarkets'], 'D1,EXITO');
    expect(requested[2].queryParameters['supermarkets'], 'D1,EXITO');
    expect(requested[0].queryParameters['owner_ref'], 'x');
  });

  test('búsqueda, sugerencias y comparación también se limitan', () async {
    ApiClient.scopeResolver = () async => ['D1'];

    await client.getJson('/api/v1/products', queryParameters: {'q': 'arroz'});
    await client.getJson('/api/v1/products/suggest', queryParameters: {'q': 'leche'});
    await client.getJson('/api/v1/products/p-80/compare');

    for (final uri in requested) {
      expect(uri.queryParameters['supermarkets'], 'D1');
    }
  });

  test('sin supermercados al alcance se envía el parámetro vacío (ninguna oferta)', () async {
    ApiClient.scopeResolver = () async => [];

    await client.getJson('/api/v1/lists/4/cost', queryParameters: {'owner_ref': 'x'});

    expect(requested.single.queryParameters.containsKey('supermarkets'), isTrue);
    expect(requested.single.queryParameters['supermarkets'], '');
  });

  test('sin ubicación (null) no se filtra nada', () async {
    ApiClient.scopeResolver = () async => null;

    await client.getJson('/api/v1/lists/4/cost', queryParameters: {'owner_ref': 'x'});

    expect(requested.single.queryParameters.containsKey('supermarkets'), isFalse);
  });

  test('las categorías SÍ se filtran por alcance (sus conteos son de lo que está a tu alcance)', () async {
    ApiClient.scopeResolver = () async => ['D1', 'EXITO'];

    await client.getJson('/api/v1/categories');

    expect(requested.single.queryParameters['supermarkets'], 'D1,EXITO');
  });

  test('tiendas, sesión y listas nunca se filtran', () async {
    ApiClient.scopeResolver = () async => ['D1'];

    await client.getJson('/api/v1/stores/nearby', queryParameters: {'lat': '1', 'lon': '2'});
    await client.getJson('/api/v1/auth/me');
    await client.getJson('/api/v1/lists', queryParameters: {'owner_ref': 'x'});

    for (final uri in requested) {
      expect(uri.queryParameters.containsKey('supermarkets'), isFalse, reason: uri.path);
    }
  });
}
