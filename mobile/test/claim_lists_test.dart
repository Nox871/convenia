import 'dart:convert';

import 'package:convenia_mobile/repositories/shopping_list_repository.dart';
import 'package:convenia_mobile/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reclamar las listas del dispositivo hace POST /lists/claim con el id del dispositivo', () async {
    late http.Request captured;
    final repository = ShoppingListRepository(
      client: ApiClient(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'claimed': 3}), 200);
        }),
      ),
    );

    final claimed = await repository.claimDeviceLists('mi-dispositivo');

    expect(claimed, 3);
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/lists/claim');
    expect(jsonDecode(captured.body), {'owner_ref': 'mi-dispositivo'});
  });
}
