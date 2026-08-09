import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:myapp/features/scoreboard/data/scoreboard_endpoint.dart';
import 'package:myapp/features/scoreboard/domain/scoreboard_payload.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:web_socket_channel/io.dart';

@immutable
class DiscoveredScoreboard {
  const DiscoveredScoreboard({required this.uri, required this.payload});

  final Uri uri;
  final ScoreboardPayload payload;

  String get host => uri.host;
  int get port => uri.port;
  String get label => '${payload.teamAName} vs ${payload.teamBName}';
}

/// Busca mesas de control en la red local para no tener que teclear la IP.
///
/// Recorre el /24 de la Wi-Fi actual probando los puertos candidatos. Dos
/// cautelas que importan:
/// - **Concurrencia limitada**: 254 hosts × 3 puertos son 762 sockets; abrirlos
///   todos a la vez reproduciría el mismo colapso que estamos arreglando.
/// - **Verificación real**: no basta con que el puerto abra; se completa el
///   handshake WebSocket y se exige un payload decodificable, para no ofrecer
///   como marcador cualquier otro servicio que escuche en el 8080.
class LanScoreboardDiscovery {
  LanScoreboardDiscovery({this.maxConcurrent = 32});

  final int maxConcurrent;

  bool _cancelled = false;

  Stream<DiscoveredScoreboard> scan({
    Duration timeout = const Duration(seconds: 6),
  }) {
    final controller = StreamController<DiscoveredScoreboard>();
    _cancelled = false;

    controller.onCancel = () => _cancelled = true;
    unawaited(_run(controller, timeout));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<DiscoveredScoreboard> controller,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    try {
      final localIp = await _localIp();
      if (localIp == null) {
        await controller.close();
        return;
      }

      final prefix = localIp.substring(0, localIp.lastIndexOf('.'));
      final targets = <Uri>[
        for (var host = 1; host <= 254; host++)
          for (final port in ScoreboardEndpoint.candidatePorts)
            if ('$prefix.$host' != localIp)
              Uri.parse('ws://$prefix.$host:$port'),
      ];

      var index = 0;
      Future<void> worker() async {
        while (true) {
          if (_cancelled || DateTime.now().isAfter(deadline)) return;
          if (index >= targets.length) return;
          final uri = targets[index++];

          final found = await _probe(uri, deadline);
          if (found != null && !_cancelled && !controller.isClosed) {
            controller.add(found);
          }
        }
      }

      await Future.wait([
        for (var i = 0; i < maxConcurrent; i++) worker(),
      ]);
    } catch (e) {
      debugPrint('LanScoreboardDiscovery: error de escaneo: $e');
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  /// Dos fases: primero un TCP barato para descartar hosts muertos, luego el
  /// handshake WebSocket solo sobre los que respondieron.
  Future<DiscoveredScoreboard?> _probe(Uri uri, DateTime deadline) async {
    try {
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: const Duration(milliseconds: 300),
      );
      socket.destroy();
    } catch (_) {
      return null;
    }

    if (_cancelled || DateTime.now().isAfter(deadline)) return null;

    IOWebSocketChannel? channel;
    try {
      channel = IOWebSocketChannel.connect(
        uri,
        connectTimeout: const Duration(milliseconds: 800),
      );
      await channel.ready;

      // El servidor manda el último marcador nada más conectar; si no llega
      // nada en 1 s, no es una mesa de control con partido abierto.
      final raw = await channel.stream.first
          .timeout(const Duration(seconds: 1));
      final payload = ScoreboardPayload.tryDecode(raw.toString());
      if (payload == null) return null;

      return DiscoveredScoreboard(uri: uri, payload: payload);
    } catch (_) {
      return null;
    } finally {
      try {
        await channel?.sink.close();
      } catch (_) {
        // Cerrar un canal que no llegó a abrirse lanza; es esperado.
      }
    }
  }

  Future<String?> _localIp() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (ip == null || !ip.contains('.')) return null;
      return ip;
    } catch (_) {
      return null;
    }
  }

  void cancel() => _cancelled = true;
}
