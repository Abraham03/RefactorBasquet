import 'dart:async';

import 'package:myapp/features/scoreboard/domain/scoreboard_payload.dart';
import 'package:myapp/features/scoreboard/domain/scoreboard_transport.dart';
import 'package:myapp/logic/match_game_controller.dart';

/// Compone el marcador y lo difunde.
///
/// Antes esto vivía dentro de `MatchControlScreen`: un widget de UI poseía el
/// servidor, serializaba el estado y difundía. Al sacarlo aquí, la pantalla
/// solo publica metadatos y este objeto se encarga del resto, con un ciclo de
/// vida ligado a la app y no al widget.
class ScoreboardBroadcaster {
  ScoreboardBroadcaster(this._publisher);

  final ScoreboardPublisher _publisher;

  /// Une las ráfagas de cambios en una sola emisión. El tick del reloj (1/s)
  /// pasa igual; lo que se evita es inundar a los clientes cuando un solo gesto
  /// dispara varias actualizaciones seguidas.
  static const Duration _coalesceWindow = Duration(milliseconds: 50);

  Timer? _coalesceTimer;
  MatchState? _pendingState;
  MatchState? _lastState;
  ScoreboardMeta? _meta;
  bool _disposed = false;

  void onState(MatchState state) {
    if (_disposed) return;
    _lastState = state;
    if (_meta == null) return; // Sin partido abierto no hay nada que difundir.
    _pendingState = state;
    _scheduleFlush();
  }

  void onMeta(ScoreboardMeta? meta) {
    if (_disposed) return;
    _meta = meta;

    if (meta == null) {
      // Se cerró el partido: que un cliente nuevo no vea el marcador anterior.
      _coalesceTimer?.cancel();
      _coalesceTimer = null;
      _pendingState = null;
      _publisher.clear();
      return;
    }

    // Cambió el partido o sus metadatos: emitir ya con el estado conocido.
    final state = _lastState;
    if (state != null) {
      _pendingState = state;
      _scheduleFlush();
    }
  }

  void _scheduleFlush() {
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(_coalesceWindow, _flush);
  }

  void _flush() {
    _coalesceTimer = null;
    if (_disposed) return;

    final state = _pendingState;
    final meta = _meta;
    _pendingState = null;
    if (state == null || meta == null) return;

    _publisher.publish(ScoreboardPayload.fromMatch(state, meta));
  }

  void dispose() {
    _disposed = true;
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
  }
}
