import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:myapp/features/scoreboard/data/scoreboard_endpoint.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Estado observable del servidor, para pintarlo en la UI (IP, puerto y
/// cuántas pantallas están realmente enganchadas).
@immutable
class PublisherStatus {
  const PublisherStatus({
    required this.isRunning,
    required this.port,
    required this.clientCount,
  });

  const PublisherStatus.stopped()
      : isRunning = false,
        port = null,
        clientCount = 0;

  final bool isRunning;
  final int? port;
  final int clientCount;

  @override
  bool operator ==(Object other) =>
      other is PublisherStatus &&
      other.isRunning == isRunning &&
      other.port == port &&
      other.clientCount == clientCount;

  @override
  int get hashCode => Object.hash(isRunning, port, clientCount);
}

/// Servidor WebSocket de la red local: difunde el marcador a la pantalla
/// externa (loopback) y a las tablets de la LAN.
class LocalWebSocketServer {
  /// Una sola instancia por `ProviderScope`, vía `localWebSocketServerProvider`.
  /// Antes era un singleton estático, lo que impedía levantar un servidor
  /// aislado por test.
  LocalWebSocketServer();

  HttpServer? _server;
  int? _port;

  final List<WebSocketChannel> _clients = [];
  final StreamController<PublisherStatus> _status =
      StreamController<PublisherStatus>.broadcast();

  /// Último marcador difundido. Se envía al vuelo a quien conecte tarde, para
  /// que la pantalla no se quede en blanco esperando el siguiente cambio.
  String? _lastPayload;

  Future<int>? _starting;

  int? get port => _port;
  int get clientCount => _clients.length;
  bool get isRunning => _server != null;
  Stream<PublisherStatus> get status => _status.stream;

  PublisherStatus get currentStatus => PublisherStatus(
        isRunning: isRunning,
        port: _port,
        clientCount: _clients.length,
      );

  /// Levanta el servidor y devuelve el puerto efectivo. Idempotente y seguro
  /// ante llamadas concurrentes.
  Future<int> startServer() {
    final port = _port;
    if (_server != null && port != null) return Future.value(port);
    return _starting ??= _start()..whenComplete(() => _starting = null);
  }

  Future<int> _start() async {
    final handler = webSocketHandler(
      (WebSocketChannel webSocket) => _registerClient(webSocket),
      // Detecta clientes zombie y mantiene viva la conexión cuando el reloj
      // está parado y no hay tráfico que impida el idle-timeout del router.
      pingInterval: const Duration(seconds: 10),
    );

    Object? lastError;
    for (final candidate in ScoreboardEndpoint.candidatePorts) {
      try {
        // `shared: false` a propósito: si otro proceso ya ocupa el puerto
        // queremos enterarnos y saltar al siguiente, no repartirnos las
        // conexiones con él en silencio.
        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          candidate,
          shared: false,
        );
        _port = candidate;
        _emitStatus();
        debugPrint('LocalWebSocketServer: escuchando en :$candidate');
        return candidate;
      } on SocketException catch (e) {
        lastError = e;
        debugPrint('LocalWebSocketServer: puerto $candidate ocupado, siguiente…');
      }
    }

    _emitStatus();
    throw StateError(
      'No hay puertos libres en ${ScoreboardEndpoint.candidatePorts}: $lastError',
    );
  }

  void _registerClient(WebSocketChannel webSocket) {
    _clients.add(webSocket);

    // Sin este `listen` el canal nunca emite `onDone`: los clientes muertos se
    // acumulaban para siempre y `broadcast` acababa escribiendo sobre sockets
    // cerrados.
    webSocket.stream.listen(
      (_) {},
      onDone: () => _removeClient(webSocket),
      onError: (_) => _removeClient(webSocket),
      cancelOnError: true,
    );

    final payload = _lastPayload;
    if (payload != null) {
      try {
        webSocket.sink.add(payload);
      } catch (_) {
        _removeClient(webSocket);
        return;
      }
    }
    _emitStatus();
  }

  void _removeClient(WebSocketChannel webSocket) {
    if (_clients.remove(webSocket)) {
      try {
        webSocket.sink.close();
      } catch (_) {
        // Ya estaba cerrado.
      }
      _emitStatus();
    }
  }

  /// Difunde a todos los clientes vivos.
  ///
  /// El `try` va **por cliente**: antes envolvía el bucle entero, así que un
  /// solo socket cerrado abortaba la iteración y todos los clientes siguientes
  /// de la lista dejaban de recibir actualizaciones para siempre. Ese era el
  /// congelamiento del marcador.
  void broadcast(String message) {
    _lastPayload = message;
    for (final client in List.of(_clients)) {
      try {
        client.sink.add(message);
      } catch (_) {
        _removeClient(client);
      }
    }
  }

  /// Olvida el último marcador para que un cliente nuevo no vea el partido
  /// anterior mientras espera el siguiente.
  void clearLastPayload() => _lastPayload = null;

  Future<void> stopServer() async {
    for (final client in List.of(_clients)) {
      try {
        await client.sink.close();
      } catch (_) {
        // Ya estaba cerrado.
      }
    }
    _clients.clear();

    await _server?.close(force: true);
    _server = null;
    _port = null;
    _lastPayload = null;
    _emitStatus();
  }

  void _emitStatus() {
    if (!_status.isClosed) _status.add(currentStatus);
  }
}
