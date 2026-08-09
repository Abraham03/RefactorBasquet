import 'package:flutter/foundation.dart';
import 'package:myapp/features/scoreboard/data/websocket_server.dart';
import 'package:myapp/features/scoreboard/domain/scoreboard_payload.dart';

export 'package:myapp/features/scoreboard/data/websocket_server.dart' show PublisherStatus;

/// Emite el marcador hacia donde sea (LAN, y mañana BLE, Nearby o lo que haga
/// falta) sin que la UI sepa por qué medio viaja.
abstract interface class ScoreboardPublisher {
  Future<void> start();

  void publish(ScoreboardPayload payload);

  /// Olvida el último marcador: quien conecte después no verá el partido
  /// anterior mientras espera datos nuevos.
  void clear();

  Future<void> stop();

  Stream<PublisherStatus> get status;

  PublisherStatus get currentStatus;
}

/// Lo que una pantalla receptora necesita saber, ya traducido del transporte.
@immutable
sealed class ScoreboardFeedEvent {
  const ScoreboardFeedEvent();
}

class FeedConnecting extends ScoreboardFeedEvent {
  const FeedConnecting({required this.attempt});
  final int attempt;
}

/// Conectado pero todavía sin marcador (p. ej. no hay partido abierto).
class FeedWaiting extends ScoreboardFeedEvent {
  const FeedWaiting();
}

class FeedData extends ScoreboardFeedEvent {
  const FeedData(this.payload);
  final ScoreboardPayload payload;
}

class FeedDisconnected extends ScoreboardFeedEvent {
  const FeedDisconnected({required this.retryIn, this.error});
  final Duration retryIn;
  final Object? error;
}

/// Recibe el marcador. Una implementación por transporte.
abstract interface class ScoreboardSubscriber {
  Stream<ScoreboardFeedEvent> subscribe(List<Uri> endpoints);
  Future<void> dispose();
}

/// Implementación LAN sobre el servidor WebSocket local.
class WebSocketScoreboardPublisher implements ScoreboardPublisher {
  WebSocketScoreboardPublisher([LocalWebSocketServer? server])
      : _server = server ?? LocalWebSocketServer.instance;

  final LocalWebSocketServer _server;

  @override
  Future<void> start() => _server.startServer();

  @override
  void publish(ScoreboardPayload payload) => _server.broadcast(payload.encode());

  @override
  void clear() => _server.clearLastPayload();

  @override
  Future<void> stop() => _server.stopServer();

  @override
  Stream<PublisherStatus> get status => _server.status;

  @override
  PublisherStatus get currentStatus => _server.currentStatus;
}
