import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/scoreboard/data/resilient_ws_client.dart';

void main() {
  group('ResilientWsClient', () {
    test('reintenta de forma lineal, no exponencial, contra un puerto cerrado',
        () async {
      // Regresión del congelamiento: el código anterior registraba `onDone` Y
      // `onError` apuntando al mismo reintento, así que cada fallo programaba
      // dos intentos nuevos (2^n). En 6 s eso pasaba de 1000 intentos.
      final client = ResilientWsClient(
        endpoints: [Uri.parse('ws://127.0.0.1:59997')],
        connectTimeout: const Duration(seconds: 1),
        debugLabel: 'test-closed-port',
      );

      var attempts = 0;
      final sub = client.events.listen((e) {
        if (e is WsConnecting) attempts++;
      });

      client.start();
      await Future<void>.delayed(const Duration(seconds: 6));
      await sub.cancel();
      await client.dispose();

      expect(attempts, greaterThan(1), reason: 'debe reintentar');
      expect(
        attempts,
        lessThanOrEqualTo(12),
        reason: 'crecimiento lineal con backoff, no exponencial',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('un solo fallo programa exactamente un reintento', () async {
      // `onDone` y `onError` llegan juntos cuando el socket muere; el cliente
      // debe emitir una sola desconexión por caída.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final sockets = <WebSocket>[];

      unawaited(() async {
        await for (final request in server) {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
        }
      }());

      final client = ResilientWsClient(
        endpoints: [Uri.parse('ws://127.0.0.1:$port')],
        debugLabel: 'test-single-retry',
      );

      var connected = 0;
      var disconnected = 0;
      final sub = client.events.listen((e) {
        if (e is WsConnected) connected++;
        if (e is WsDisconnected) disconnected++;
      });

      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(connected, 1, reason: 'debe haber conectado');

      // Matar la conexión desde el servidor: dispara onDone + onError.
      for (final s in sockets) {
        await s.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(disconnected, 1, reason: 'una caída => una sola desconexión');

      await sub.cancel();
      await client.dispose();
      await server.close(force: true);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('entrega los mensajes recibidos y se reconecta sola', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      unawaited(() async {
        await for (final request in server) {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.add('hola');
        }
      }());

      final client = ResilientWsClient(
        endpoints: [Uri.parse('ws://127.0.0.1:$port')],
        debugLabel: 'test-messages',
      );

      final received = <String>[];
      final sub = client.events.listen((e) {
        if (e is WsMessage) received.add(e.raw);
      });

      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(received, contains('hola'));

      await sub.cancel();
      await client.dispose();
      await server.close(force: true);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('dispose detiene los reintentos', () async {
      final client = ResilientWsClient(
        endpoints: [Uri.parse('ws://127.0.0.1:59996')],
        connectTimeout: const Duration(milliseconds: 500),
        debugLabel: 'test-dispose',
      );

      var attempts = 0;
      final sub = client.events.listen((e) {
        if (e is WsConnecting) attempts++;
      });

      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await client.dispose();
      final attemptsAtDispose = attempts;

      await Future<void>.delayed(const Duration(seconds: 3));
      expect(attempts, attemptsAtDispose, reason: 'no reintenta tras dispose');

      await sub.cancel();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
