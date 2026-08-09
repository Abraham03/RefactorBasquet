import 'dart:async';

import 'package:myapp/core/scoreboard/resilient_ws_client.dart';
import 'package:myapp/core/scoreboard/scoreboard_payload.dart';
import 'package:myapp/core/scoreboard/scoreboard_transport.dart';

/// Traduce los eventos de transporte del [ResilientWsClient] a eventos de
/// dominio del marcador.
///
/// Aquí vive, una sola vez, la lógica que antes estaba duplicada entre la
/// pantalla externa y el cliente por IP: conectar, esperar, decodificar y
/// avisar de las caídas.
class WebSocketScoreboardSubscriber implements ScoreboardSubscriber {
  ResilientWsClient? _client;
  StreamSubscription<WsClientEvent>? _clientSub;
  StreamController<ScoreboardFeedEvent>? _controller;

  @override
  Stream<ScoreboardFeedEvent> subscribe(List<Uri> endpoints) {
    // Un suscriptor, una conexión: resuscribirse reemplaza la anterior.
    _teardown();

    final controller = StreamController<ScoreboardFeedEvent>.broadcast();
    _controller = controller;

    final client = ResilientWsClient(
      endpoints: endpoints,
      debugLabel: 'scoreboard-sub',
    );
    _client = client;

    _clientSub = client.events.listen((event) {
      if (controller.isClosed) return;
      switch (event) {
        case WsConnecting(:final attempt):
          controller.add(FeedConnecting(attempt: attempt));
        case WsConnected():
          controller.add(const FeedWaiting());
        case WsMessage(:final raw):
          final payload = ScoreboardPayload.tryDecode(raw);
          // Un mensaje ilegible no debe tirar la pantalla: se ignora.
          if (payload != null) controller.add(FeedData(payload));
        case WsDisconnected(:final retryIn, :final error):
          controller.add(FeedDisconnected(retryIn: retryIn, error: error));
      }
    });

    client.start();
    return controller.stream;
  }

  void _teardown() {
    _clientSub?.cancel();
    _clientSub = null;
    _client?.dispose();
    _client = null;
    _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    _teardown();
  }
}
