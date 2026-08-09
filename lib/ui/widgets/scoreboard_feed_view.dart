import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/scoreboard/scoreboard_payload.dart';
import 'package:myapp/core/scoreboard/scoreboard_transport.dart';
import 'package:myapp/core/scoreboard/ws_scoreboard_subscriber.dart';
import 'package:myapp/ui/widgets/tv_scoreboard_widget.dart';

/// Un feed por lista de endpoints. `autoDispose` cierra el socket al salir de
/// la pantalla sin necesidad de un `dispose` manual en cada consumidor.
final scoreboardFeedProvider = StreamProvider.autoDispose
    .family<ScoreboardFeedEvent, String>((ref, endpointsKey) {
  final endpoints = endpointsKey.split(',').map(Uri.parse).toList();
  final subscriber = WebSocketScoreboardSubscriber();
  ref.onDispose(subscriber.dispose);
  return subscriber.subscribe(endpoints);
});

/// Pantalla receptora del marcador, compartida por la TV externa y la tablet.
///
/// Unifica lo que antes eran dos implementaciones copiadas (conectar,
/// decodificar, pintar) que se comportaban distinto ante un corte de red.
class ScoreboardFeedView extends ConsumerStatefulWidget {
  const ScoreboardFeedView({
    super.key,
    required this.endpoints,
    this.showConnectionBanner = true,
    this.onDisconnectRequested,
  });

  final List<Uri> endpoints;

  /// La TV de la cancha no muestra avisos de red al público; la tablet del
  /// operador sí.
  final bool showConnectionBanner;

  final VoidCallback? onDisconnectRequested;

  @override
  ConsumerState<ScoreboardFeedView> createState() => _ScoreboardFeedViewState();
}

class _ScoreboardFeedViewState extends ConsumerState<ScoreboardFeedView> {
  /// Se conserva entre caídas: un corte de Wi-Fi de dos segundos no debe dejar
  /// la pantalla de la pared en blanco.
  ScoreboardPayload? _lastPayload;
  bool _isLive = false;
  Duration? _retryIn;

  String get _key => widget.endpoints.map((u) => u.toString()).join(',');

  void _handleEvent(ScoreboardFeedEvent event) {
    switch (event) {
      case FeedData(:final payload):
        _lastPayload = payload;
        _isLive = true;
        _retryIn = null;
      case FeedWaiting():
        _isLive = true;
        _retryIn = null;
      case FeedConnecting():
        break;
      case FeedDisconnected(:final retryIn):
        _isLive = false;
        _retryIn = retryIn;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ScoreboardFeedEvent>>(
      scoreboardFeedProvider(_key),
      (_, next) {
        final event = next.valueOrNull;
        if (event == null) return;
        setState(() => _handleEvent(event));
      },
    );
    // Necesario para que el provider se construya (y el socket se abra).
    ref.watch(scoreboardFeedProvider(_key));

    final payload = _lastPayload;

    return Stack(
      children: [
        if (payload == null)
          _buildWaiting()
        else
          Center(
            child: SafeArea(
              child: TvScoreboardWidget(
                state: payload.state,
                teamAName: payload.teamAName,
                teamBName: payload.teamBName,
                teamAFouls: payload.teamAFouls,
                teamBFouls: payload.teamBFouls,
              ),
            ),
          ),
        if (payload != null && !_isLive && widget.showConnectionBanner)
          _buildReconnectBanner(),
        if (widget.onDisconnectRequested != null)
          Positioned(
            top: 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.white24),
              onPressed: widget.onDisconnectRequested,
            ),
          ),
      ],
    );
  }

  Widget _buildWaiting() {
    final retry = _retryIn;
    final message = _isLive
        ? "Conectado. Esperando el marcador…"
        : retry == null
            ? "Conectando…"
            : "Sin respuesta. Reintentando en ${formatRetry(retry)}…";

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.orangeAccent),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReconnectBanner() {
    final retry = _retryIn;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.shade900.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  retry == null
                      ? "Reconectando…"
                      : "Sin señal. Reconectando en ${formatRetry(retry)}…",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatRetry(Duration d) {
  final seconds = (d.inMilliseconds / 1000).ceil();
  return seconds <= 1 ? "1 s" : "$seconds s";
}
