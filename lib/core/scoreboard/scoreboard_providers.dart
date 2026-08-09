import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/scoreboard/scoreboard_broadcaster.dart';
import 'package:myapp/core/scoreboard/scoreboard_payload.dart';
import 'package:myapp/core/scoreboard/scoreboard_transport.dart';
import 'package:myapp/core/service/external_display_service.dart';
import 'package:myapp/logic/match_game_controller.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Servidor del marcador. Vive tanto como la app, no como una pantalla: así la
/// IP está disponible desde el menú y una tablet puede enlazarse antes de que
/// empiece el partido.
final scoreboardPublisherProvider = Provider<ScoreboardPublisher>((ref) {
  final publisher = WebSocketScoreboardPublisher();
  publisher.start();
  ref.onDispose(publisher.stop);
  return publisher;
});

final publisherStatusProvider = StreamProvider<PublisherStatus>((ref) {
  final publisher = ref.watch(scoreboardPublisherProvider);
  return publisher.status;
});

/// IP de la Wi-Fi local, para dictársela al operador de la tablet.
final localIpProvider = FutureProvider<String?>((ref) async {
  try {
    return await NetworkInfo().getWifiIP();
  } catch (_) {
    return null;
  }
});

/// Metadatos del partido en curso. La pantalla de control solo ESCRIBE aquí;
/// ponerlo a `null` equivale a "no hay partido" y limpia el marcador difundido.
final scoreboardMetaProvider = StateProvider<ScoreboardMeta?>((ref) => null);

/// Difusión del marcador. Se suscribe al estado del partido a nivel de app, sin
/// que ninguna pantalla tenga que acordarse de emitir.
final scoreboardBroadcasterProvider = Provider<ScoreboardBroadcaster>((ref) {
  final broadcaster = ScoreboardBroadcaster(
    ref.watch(scoreboardPublisherProvider),
  );

  ref.listen<MatchState>(
    matchGameProvider,
    (_, next) => broadcaster.onState(next),
    fireImmediately: true,
  );
  ref.listen<ScoreboardMeta?>(
    scoreboardMetaProvider,
    (_, next) => broadcaster.onMeta(next),
    fireImmediately: true,
  );

  ref.onDispose(broadcaster.dispose);
  return broadcaster;
});

/// Pantalla externa (HDMI / AnyCast) vigilando el DisplayManager.
final externalDisplayProvider = Provider<ExternalDisplayService>((ref) {
  final service = ExternalDisplayService.instance;
  service.start();
  return service;
});

final externalDisplayStatusProvider = StreamProvider<ExternalDisplayStatus>((ref) {
  return ref.watch(externalDisplayProvider).statusStream;
});
