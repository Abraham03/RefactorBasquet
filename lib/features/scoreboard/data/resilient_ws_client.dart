import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

/// Eventos de transporte. Deliberadamente NO conocen el dominio del marcador:
/// este cliente solo sabe de sockets, y quien lo consume decide cómo interpretar
/// [WsMessage.raw]. Así el mismo transporte sirve para cualquier payload (OCP).
@immutable
sealed class WsClientEvent {
  const WsClientEvent();
}

class WsConnecting extends WsClientEvent {
  const WsConnecting({required this.attempt, required this.endpoint});
  final int attempt;
  final Uri endpoint;
}

class WsConnected extends WsClientEvent {
  const WsConnected({required this.endpoint});
  final Uri endpoint;
}

class WsMessage extends WsClientEvent {
  const WsMessage(this.raw);
  final String raw;
}

class WsDisconnected extends WsClientEvent {
  const WsDisconnected({required this.retryIn, this.error});
  final Duration retryIn;
  final Object? error;
}

/// Cliente WebSocket con reconexión automática de un solo vuelo.
///
/// Sustituye al patrón que congelaba la app: registrar `onDone` **y** `onError`
/// apuntando al mismo reintento hace que cada fallo programe DOS intentos
/// nuevos (el stream emite el error y después se cierra), con crecimiento 2^n
/// hasta el ANR. Aquí el reintento es idempotente por diseño.
///
/// Garantías:
/// - Un fallo programa **exactamente un** reintento, lleguen `onDone` y
///   `onError` juntos o por separado.
/// - Nunca hay dos intentos de conexión en vuelo.
/// - Cada intento cierra el canal y cancela la suscripción anteriores.
/// - El fallo se detecta en [connectTimeout], no en el timeout TCP del SO.
/// - Backoff exponencial con techo y jitter, y rotación entre [endpoints]
///   (así el isolate secundario encuentra el puerto de respaldo sin compartir
///   memoria con el principal).
class ResilientWsClient {
  ResilientWsClient({
    required List<Uri> endpoints,
    this.connectTimeout = const Duration(seconds: 5),
    this.pingInterval = const Duration(seconds: 10),
    this.maxBackoff = const Duration(seconds: 8),
    this.debugLabel = 'ws',
  })  : assert(endpoints.isNotEmpty, 'Se requiere al menos un endpoint'),
        _endpoints = List.unmodifiable(endpoints);

  final List<Uri> _endpoints;
  final Duration connectTimeout;
  final Duration pingInterval;
  final Duration maxBackoff;
  final String debugLabel;

  final StreamController<WsClientEvent> _events =
      StreamController<WsClientEvent>.broadcast();
  final Random _random = Random();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retryTimer;

  bool _started = false;
  bool _connecting = false;
  bool _disposed = false;

  /// Impide que `onDone` + `onError` del mismo fallo programen dos reintentos.
  bool _retryScheduled = false;

  int _attempt = 0;
  int _endpointIndex = 0;

  Stream<WsClientEvent> get events => _events.stream;

  bool get isConnected => _channel != null && !_connecting;

  Uri get currentEndpoint => _endpoints[_endpointIndex % _endpoints.length];

  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_disposed || _connecting) return;
    _connecting = true;

    await _teardownConnection();
    if (_disposed) {
      _connecting = false;
      return;
    }

    final uri = currentEndpoint;
    _emit(WsConnecting(attempt: _attempt + 1, endpoint: uri));

    try {
      final channel = IOWebSocketChannel.connect(
        uri,
        connectTimeout: connectTimeout,
        pingInterval: pingInterval,
      );
      // `connect` es perezoso y no lanza aquí: sin `ready` el fallo tardaría
      // el timeout TCP del sistema (30-120 s) en manifestarse.
      await channel.ready;
      if (_disposed) {
        await _closeChannel(channel);
        _connecting = false;
        return;
      }

      _channel = channel;
      _attempt = 0;
      _retryScheduled = false;
      _connecting = false;
      _emit(WsConnected(endpoint: uri));

      _sub = channel.stream.listen(
        (dynamic message) => _emit(WsMessage(message.toString())),
        onDone: () => _onConnectionLost(null),
        onError: (Object error) => _onConnectionLost(error),
        cancelOnError: true,
      );
    } catch (e) {
      _connecting = false;
      _onConnectionLost(e);
    }
  }

  /// Punto único de fallo. Idempotente: solo el primer aviso de una misma
  /// caída programa reintento.
  void _onConnectionLost(Object? error) {
    if (_disposed || _retryScheduled) return;
    _retryScheduled = true;
    _connecting = false;

    _attempt++;
    _endpointIndex = (_endpointIndex + 1) % _endpoints.length;

    final delay = _backoffDelay(_attempt);
    _retryTimer?.cancel();
    _emit(WsDisconnected(retryIn: delay, error: error));

    if (kDebugMode) {
      debugPrint(
        '[$debugLabel] conexión perdida (intento $_attempt): $error. '
        'Reintento en ${delay.inMilliseconds}ms',
      );
    }

    _retryTimer = Timer(delay, () {
      _retryScheduled = false;
      unawaited(_connect());
    });
  }

  /// 1s, 2s, 4s, 8s… con techo [maxBackoff] y jitter de ±20 % para que varios
  /// clientes que caen a la vez no reintenten en bloque.
  Duration _backoffDelay(int attempt) {
    final exponent = (attempt - 1).clamp(0, 10);
    final baseMs = 1000 * pow(2, exponent).toInt();
    final cappedMs = min(baseMs, maxBackoff.inMilliseconds);
    final jitter = (cappedMs * 0.2 * (_random.nextDouble() * 2 - 1)).round();
    return Duration(milliseconds: max(250, cappedMs + jitter));
  }

  Future<void> _teardownConnection() async {
    final sub = _sub;
    _sub = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {
        // Cancelar una suscripción ya finalizada no es un error accionable.
      }
    }

    final channel = _channel;
    _channel = null;
    if (channel != null) await _closeChannel(channel);
  }

  Future<void> _closeChannel(IOWebSocketChannel channel) async {
    try {
      await channel.sink.close();
    } catch (_) {
      // Un canal que nunca llegó a conectar lanza al cerrarse; es esperado.
    }
  }

  void _emit(WsClientEvent event) {
    if (_disposed || _events.isClosed) return;
    _events.add(event);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _teardownConnection();
    await _events.close();
  }
}
