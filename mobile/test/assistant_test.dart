import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:convenia_mobile/core/api_exception.dart';
import 'package:convenia_mobile/repositories/assistant_repository.dart';
import 'package:convenia_mobile/screens/assistant_screen.dart';

/// Repositorio falso para probar la pantalla sin red.
class _FakeAssistant extends AssistantRepository {
  final List<String> asked = [];
  final Future<String> Function(String) reply;

  _FakeAssistant(this.reply) : super(client: MockClient((_) async => http.Response('{}', 200)));

  @override
  Future<String> ask(String message) {
    asked.add(message);
    return reply(message);
  }
}

void main() {
  group('AssistantRepository', () {
    test('envía el mensaje con la sesión y devuelve la respuesta del agente', () async {
      late http.Request seen;
      final repo = AssistantRepository(
        url: 'http://n8n.test/webhook/x/chat',
        sessionId: 'sesion-1',
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'output': ' Hola, soy ConveniaBot. '}), 200, headers: {'content-type': 'application/json'});
        }),
      );

      expect(await repo.ask('Hola'), 'Hola, soy ConveniaBot.');
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://n8n.test/webhook/x/chat');
      expect(jsonDecode(seen.body), {'action': 'sendMessage', 'sessionId': 'sesion-1', 'chatInput': 'Hola'});
    });

    test('un error del servidor se convierte en ApiException', () async {
      final repo = AssistantRepository(client: MockClient((_) async => http.Response('boom', 500)));
      expect(() => repo.ask('Hola'), throwsA(isA<ApiException>()));
    });

    test('una respuesta vacía o sin el campo output es un error, no un texto en blanco', () async {
      final vacia = AssistantRepository(client: MockClient((_) async => http.Response(jsonEncode({'output': '  '}), 200)));
      final sinCampo = AssistantRepository(client: MockClient((_) async => http.Response(jsonEncode({'otro': 1}), 200)));
      expect(() => vacia.ask('x'), throwsA(isA<ApiException>()));
      expect(() => sinCampo.ask('x'), throwsA(isA<ApiException>()));
    });

    test('una respuesta que no es JSON es un error controlado', () async {
      final repo = AssistantRepository(client: MockClient((_) async => http.Response('<html>', 200)));
      expect(() => repo.ask('x'), throwsA(isA<ApiException>()));
    });

    test('cada conversación tiene su propia sesión', () {
      expect(AssistantRepository().sessionId, isNot(AssistantRepository().sessionId));
    });
  });

  group('AssistantScreen', () {
    testWidgets('muestra el saludo y sugerencias, y responde una pregunta', (tester) async {
      final respuesta = Completer<String>();
      final fake = _FakeAssistant((_) => respuesta.future);
      await tester.pumpWidget(MaterialApp(home: AssistantScreen(repository: fake)));

      expect(find.textContaining('Hola, soy ConveniaBot'), findsOneWidget);
      expect(find.byKey(const Key('assistant_suggestion_0')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('assistant_input')), 'precio del café');
      await tester.tap(find.byKey(const Key('assistant_send')));
      await tester.pump();
      expect(find.byKey(const Key('assistant_typing')), findsOneWidget);
      respuesta.complete('El café Juan Valdez cuesta \$35.990 en Jumbo.');
      await tester.pumpAndSettle();

      expect(fake.asked, ['precio del café']);
      expect(find.text('precio del café'), findsOneWidget);
      expect(find.textContaining('35.990 en Jumbo'), findsOneWidget);
      expect(find.byKey(const Key('assistant_typing')), findsNothing);
    });

    testWidgets('una sugerencia se envía como pregunta', (tester) async {
      final fake = _FakeAssistant((_) async => 'Respuesta');
      await tester.pumpWidget(MaterialApp(home: AssistantScreen(repository: fake)));
      await tester.tap(find.byKey(const Key('assistant_suggestion_0')));
      await tester.pumpAndSettle();
      expect(fake.asked, ['¿Cuánto cuesta la leche?']);
    });

    testWidgets('si el asistente falla lo dice y permite reintentar', (tester) async {
      var intento = 0;
      final fake = _FakeAssistant((_) async {
        intento++;
        if (intento == 1) throw const ApiException('No se pudo conectar con el asistente.');
        return 'Ya estoy de vuelta.';
      });
      await tester.pumpWidget(MaterialApp(home: AssistantScreen(repository: fake)));

      await tester.enterText(find.byKey(const Key('assistant_input')), 'hola');
      await tester.tap(find.byKey(const Key('assistant_send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudo conectar con el asistente.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('assistant_retry')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ya estoy de vuelta.'), findsOneWidget);
      expect(find.byKey(const Key('assistant_retry')), findsNothing);
    });

    testWidgets('un mensaje vacío no se envía', (tester) async {
      final fake = _FakeAssistant((_) async => 'x');
      await tester.pumpWidget(MaterialApp(home: AssistantScreen(repository: fake)));
      await tester.enterText(find.byKey(const Key('assistant_input')), '   ');
      await tester.tap(find.byKey(const Key('assistant_send')));
      await tester.pump();
      expect(fake.asked, isEmpty);
    });
  });
}
