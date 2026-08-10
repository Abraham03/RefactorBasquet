import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/features/scoreboard/data/scoreboard_broadcaster.dart';
import 'package:myapp/features/scoreboard/domain/scoreboard_payload.dart';
import 'package:myapp/features/scoreboard/domain/scoreboard_transport.dart';
import 'package:myapp/features/scoreboard/data/external_display_service.dart';
import 'package:myapp/features/scoreboard/data/websocket_server.dart';
import 'package:myapp/features/scoreboard/data/ws_scoreboard_subscriber.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Servidor WebSocket de la LAN. Una sola instancia por `ProviderScope`;
/// antes era un singleton estático inaccesible desde los tests.
final localWebSocketServerProvider = Provider<LocalWebSocketServer>((ref) {
  return LocalWebSocketServer();
});

/// Servidor del marcador. Vive tanto como la app, no como una pantalla: así la
/// IP está disponible desde el menú y una tablet puede enlazarse antes de que
/// empiece el partido.
final scoreboardPublisherProvider = Provider<ScoreboardPublisher>((ref) {
  final publisher = WebSocketScoreboardPublisher(
    ref.watch(localWebSocketServerProvider),
  );
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
///
/// ÚNICO punto de arranque del servicio. Antes se arrancaba también desde
/// `MyApp.initState`, así que había dos `start()` compitiendo.
final externalDisplayProvider = Provider<ExternalDisplayService>((ref) {
  final service = ExternalDisplayService();
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

final externalDisplayStatusProvider = StreamProvider<ExternalDisplayStatus>((ref) {
  return ref.watch(externalDisplayProvider).statusStream;
});

/// Un feed por lista de endpoints. `autoDispose` cierra el socket al salir de
/// la pantalla sin necesidad de un `dispose` manual en cada consumidor.
final scoreboardFeedProvider = StreamProvider.autoDispose
    .family<ScoreboardFeedEvent, String>((ref, endpointsKey) {
  final endpoints = endpointsKey.split(',').map(Uri.parse).toList();
  final subscriber = WebSocketScoreboardSubscriber();
  ref.onDispose(subscriber.dispose);
  return subscriber.subscribe(endpoints);
});
