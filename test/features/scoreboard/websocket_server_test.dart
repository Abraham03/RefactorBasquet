import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/scoreboard/data/websocket_server.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  group('LocalWebSocketServer', () {
    late int port;

    setUp(() async {
      port = await LocalWebSocketServer.instance.startServer();
    });

    tearDown(() async {
      await LocalWebSocketServer.instance.stopServer();
    });

    test('un cliente muerto no impide que los demás reciban', () async {
      // Regresión del marcador congelado: `broadcast` envolvía el bucle entero
      // en un try, así que un `sink.add` sobre un socket cerrado abortaba la
      // iteración y todos los clientes posteriores dejaban de actualizarse.
      final server = LocalWebSocketServer.instance;

      final dead = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
      final aliveA = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
      final aliveB = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
      await Future.wait([dead.ready, aliveA.ready, aliveB.ready]);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(server.clientCount, 3);

      final receivedA = <String>[];
      final receivedB = <String>[];
      aliveA.stream.listen((m) => receivedA.add(m.toString()));
      aliveB.stream.listen((m) => receivedB.add(m.toString()));

      await dead.sink.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      server.broadcast('{"scoreA":10}');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(receivedA, contains('{"scoreA":10}'));
      expect(receivedB, contains('{"scoreA":10}'));
      expect(server.clientCount, 2, reason: 'el cliente muerto se depura');

      await aliveA.sink.close();
      await aliveB.sink.close();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('un cliente que conecta tarde recibe el último marcador', () async {
      final server = LocalWebSocketServer.instance;
      server.broadcast('{"scoreA":42}');

      final late = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
      await late.ready;

      final first = await late.stream.first;
      expect(first, '{"scoreA":42}');

      await late.sink.close();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('clearLastPayload evita mostrar el partido anterior', () async {
      final server = LocalWebSocketServer.instance;
      server.broadcast('{"scoreA":42}');
      server.clearLastPayload();

      final client = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
      await client.ready;

      var receivedAnything = false;
      client.stream.listen((_) => receivedAnything = true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(receivedAnything, isFalse);
      await client.sink.close();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('startServer es idempotente y devuelve el mismo puerto', () async {
      final a = await LocalWebSocketServer.instance.startServer();
      final b = await LocalWebSocketServer.instance.startServer();
      expect(a, b);
      expect(a, port);
    });
  });
}
