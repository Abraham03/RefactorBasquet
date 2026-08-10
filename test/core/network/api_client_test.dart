// Tests de la capa de transporte.
//
// Esto era IMPOSIBLE antes de la Fase 3: `ApiService` usaba las funciones
// top-level `http.post` / `http.get`, que no admiten inyección de un cliente.
// Ahora `ApiClient` recibe un `http.Client`, así que se puede provocar cada
// modo de fallo sin tocar la red.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapp/core/errors/app_exception.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/core/network/result.dart';

/// Cliente que responde siempre lo mismo y recuerda la última petición.
MockClient _respond(
  String body, {
  int status = 200,
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    return http.Response(body, status);
  });
}

const String _okEnvelope = '{"status":"success","data":{"newId":"7"}}';

ApiClient _clientWith(http.Client inner) =>
    ApiClient(client: inner, baseUrl: 'https://example.test/api.php');

void main() {
  group('camino feliz', () {
    test(
      '200 con status success devuelve Ok y pasa `data` al decode',
      () async {
        final api = _clientWith(_respond(_okEnvelope));

        final result = await api.post(
          'create_venue',
          body: {'name': 'Gimnasio'},
          decode: (data) => (data! as Map)['newId'] as String,
        );

        expect(result, isA<Ok<String>>());
        expect(result.valueOrNull, '7');
      },
    );

    test('201 también cuenta como éxito', () async {
      // El backend usa 200 y 201 indistintamente; `_checkResponse` ya lo
      // contemplaba, pero los 25 métodos que lo inlineaban podían olvidarlo.
      final api = _clientWith(_respond(_okEnvelope, status: 201));

      final result = await api.post(
        'create_venue',
        body: const {},
        decode: (_) => 'ok',
      );

      expect(result.isOk, isTrue);
    });
  });

  group('traducción de fallos', () {
    test('500 -> HttpStatusException con el código', () async {
      final api = _clientWith(_respond('boom', status: 500));

      final result = await api.post(
        'create_venue',
        body: const {},
        decode: (_) => 'x',
      );

      final error = result.errorOrNull;
      expect(error, isA<HttpStatusException>());
      expect((error! as HttpStatusException).statusCode, 500);
    });

    test(
      'status != success -> ApiBusinessException con el mensaje del backend',
      () async {
        // Este es el caso que el viejo `Future<bool>` destruía: el servidor
        // explicaba POR QUÉ y la app solo sabía "false".
        final api = _clientWith(
          _respond('{"status":"error","message":"Ya hay partidos jugados"}'),
        );

        final result = await api.post(
          'generate_fixture',
          body: const {},
          decode: (_) => 'x',
        );

        final error = result.errorOrNull;
        expect(error, isA<ApiBusinessException>());
        expect(error!.message, 'Ya hay partidos jugados');
      },
    );

    test('JSON malformado -> ParseException', () async {
      final api = _clientWith(_respond('<html>error 502</html>'));

      final result = await api.post(
        'create_venue',
        body: const {},
        decode: (_) => 'x',
      );

      expect(result.errorOrNull, isA<ParseException>());
    });

    test(
      'un decode que revienta -> ParseException, no una excepción suelta',
      () async {
        final api = _clientWith(_respond('{"status":"success","data":null}'));

        final result = await api.post(
          'create_venue',
          body: const {},
          decode: (data) => (data! as Map)['nope'] as String,
        );

        expect(result.errorOrNull, isA<ParseException>());
      },
    );

    test('SocketException -> NetworkException', () async {
      final api = _clientWith(
        MockClient((_) async => throw const SocketException('sin ruta')),
      );

      final result = await api.post(
        'create_venue',
        body: const {},
        decode: (_) => 'x',
      );

      expect(result.errorOrNull, isA<NetworkException>());
    });

    test('timeout -> RequestTimeoutException', () async {
      // Antes NO había timeout: una red que aceptaba la conexión pero no
      // respondía dejaba la app colgada con el loader puesto para siempre.
      final api = ApiClient(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response(_okEnvelope, 200);
        }),
        baseUrl: 'https://example.test/api.php',
        timeout: const Duration(milliseconds: 20),
      );

      final result = await api.post(
        'create_venue',
        body: const {},
        decode: (_) => 'x',
      );

      expect(result.errorOrNull, isA<RequestTimeoutException>());
    });
  });

  group('construcción de la petición (contrato I2)', () {
    test('get pone la acción y respeta el orden de los parámetros', () async {
      late http.Request captured;
      final api = _clientWith(
        _respond(_okEnvelope, onRequest: (r) => captured = r),
      );

      await api.get(
        'get_team_scheduling_status',
        query: {'tournament_id': 'T1', 'round_id': '2'},
        decode: (_) => null,
      );

      expect(
        captured.url.toString(),
        'https://example.test/api.php'
        '?action=get_team_scheduling_status&tournament_id=T1&round_id=2',
      );
      expect(captured.method, 'GET');
    });

    test('post pone la acción en la query y el Content-Type JSON', () async {
      late http.Request captured;
      final api = _clientWith(
        _respond(_okEnvelope, onRequest: (r) => captured = r),
      );

      await api.post(
        'update_venue',
        body: {'id': '5', 'name': 'Gimnasio'},
        decode: (_) => null,
      );

      expect(
        captured.url.toString(),
        'https://example.test/api.php?action=update_venue',
      );
      expect(captured.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(captured.body), {'id': '5', 'name': 'Gimnasio'});
    });

    test(
      'postActionInBody NO pone query y mete la acción primero en el body',
      () async {
        // Tres endpoints del backend esperan la acción dentro del cuerpo.
        // Cambiarlo rompería el contrato.
        late http.Request captured;
        final api = _clientWith(
          _respond(_okEnvelope, onRequest: (r) => captured = r),
        );

        await api.postActionInBody(
          'generate_fixture',
          body: {'tournament_id': 'T1'},
          decode: (_) => null,
        );

        expect(captured.url.toString(), 'https://example.test/api.php');
        expect(
          captured.body,
          '{"action":"generate_fixture","tournament_id":"T1"}',
        );
      },
    );
  });
}
