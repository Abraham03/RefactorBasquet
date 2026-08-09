# Plan: Pantalla Externa (HDMI/AnyCast) + Marcador Remoto por IP

> **Documento vivo.** Se marca cada casilla al completar **y verificar**, y se edita cuando una prueba
> falle. No se avanza de etapa sin marcar la anterior.

## Protocolo de seguimiento

- `[ ]` pendiente · `[~]` en progreso · `[x]` hecho **y verificado** · `[!]` falló, ver nota
- Una tarea solo pasa a `[x]` cuando su verificación (columna *Verificación* de cada etapa) pasa.
- **Si una prueba en dispositivo real no queda:** marcar `[!]`, añadir debajo un bloque
  `> **Hallazgo <fecha>:** síntoma observado → causa → cambio de plan`, y **modificar las tareas
  afectadas en este mismo archivo** antes de seguir tocando código.
- Al cerrar una etapa: anotar el hash del commit al lado del título de la etapa.

## Estado actual (2026-08-09)

**Etapas 0 a 5: código completo y verificado en escritorio.**

| Comprobación | Resultado |
|---|---|
| `flutter analyze lib/ test/` | 0 errores, 0 warnings (5 *info* preexistentes ajenos a este trabajo) |
| `flutter test test/scoreboard/` | **29/29 pasan** |
| `flutter build apk --debug` | OK |

`test/widget_test.dart` (plantilla del contador de Flutter, ajena a esta app) falla, pero **ya fallaba
en `HEAD` antes de estos cambios** — verificado en un worktree limpio. No se tocó.

**Falta:** validación en dispositivo con el dongle real y dos equipos en la misma Wi-Fi. Ver la
checklist de aceptación al final.

---

## Context

El APK entregado al cliente **se congela mientras intenta conectarse**. La causa raíz está identificada
y verificada en código, y no es un problema de red: es una bomba de reconexión exponencial.

`lib/main.dart:139-140` registra **dos** callbacks que disparan el mismo reintento:

```dart
_channel!.stream.listen(
  (message) {...},
  onDone:  () => _retryConnection(),   // ①
  onError: (e) => _retryConnection(),  // ②
);
```

Al fallar la conexión a `ws://127.0.0.1:8080` el stream **emite el error y después se cierra**
(`cancelOnError` es `false` por defecto), así que corren ① y ② → cada intento fallido programa **dos**
nuevos. Además `_connectToLocalhost()` nunca cierra el canal anterior ni cancela la suscripción previa.
Crecimiento `2^n`: a los ~20 s hay cientos de miles de `WebSocket.connect` pendientes → ANR y OOM.

Se dispara **siempre**, porque `main.dart:42-44` muestra el scoreboard externo al arrancar la app, pero
el servidor WebSocket solo se levanta dentro de `MatchControlScreen.initState`
(`match_control_screen.dart:98`): con el AnyCast conectado y **fuera** de un partido, la app entra en el
bucle desde el primer segundo.

Alrededor hay 12 defectos más confirmados y deuda estructural (la pantalla del partido posee el servidor
y la difusión, el JSON escrito a mano en 3 archivos, dos receptores duplicados).

**Resultado esperado:** HDMI/AnyCast y marcador por IP estables un partido completo, con recuperación
automática de cortes, descubrimiento de red sin teclear IP, y el subsistema desacoplado de la UI.

---

## Inventario de defectos (referencia para las etapas)

| # | Defecto | Ubicación |
|---|---|---|
| **0** | Reintento exponencial `2^n`: `onDone` + `onError` disparan ambos `_retryConnection()`; no se cierra el canal previo ni se cancela la suscripción | `lib/main.dart:139-140`, `148-154` |
| **0b** | El receptor arranca al abrir la app pero el servidor solo existe dentro del partido → bucle en vacío | `lib/main.dart:42-44` vs `lib/ui/match_control_screen.dart:98` |
| 1 | `connectedDisplaysChangedStream` del plugin nunca se usa → el dongle que enlaza 10-30 s tarde no dispara nada | `lib/core/service/external_display_service.dart` |
| 2 | `_isShowing` se desincroniza: el nativo hace `Presentation.onStop()→cleanup()` al desconectar, Dart sigue en `true`, y el guard impide volver a mostrar sin reiniciar | `external_display_service.dart:26` |
| 3 | `displays[1]` sobre `getDisplays()` **sin categoría** → incluye displays virtuales de grabación/overlay | `external_display_service.dart:30-31` |
| 4 | Detección solo en 3 momentos puntuales, sin reintentos escalonados | `main.dart:42,53` |
| 5 | `broadcast()` se rompe entero: un `sink.add` sobre canal cerrado lanza dentro del `for` y los clientes restantes dejan de recibir para siempre; `_clients` nunca se depura | `websocket_server.dart:28-33` |
| 6 | Sin `pingInterval` → clientes zombie invisibles; con el reloj parado el AP mata el socket por idle | `websocket_server.dart:20` |
| 7 | `TextInputType.number` no ofrece `.` ni `:` en la mayoría de IMEs Android → no se puede teclear la IP | `client_scoreboard_screen.dart:149` |
| 8 | `WebSocketChannel.connect` es lazy y no lanza en el `try`; sin `ready` ni timeout el spinner gira hasta el timeout TCP del SO. Sin reconexión | `client_scoreboard_screen.dart:41-77` |
| 9 | La IP solo se ve dentro del partido → no se puede preparar la tablet antes | `match_control_screen.dart:168-180` |
| 10 | Puerto `8080` hardcodeado en 3 archivos; `shared: true` deja que otra app robe conexiones | `websocket_server.dart:25`, `main.dart:121`, `client_scoreboard_screen.dart:36` |
| 11 | `_lastPayload` nunca se limpia entre partidos → el cliente nuevo ve el marcador anterior | `websocket_server.dart:15` |
| 12 | Manifest malformado: `android:icon=…>` cierra la etiqueta y deja `usesCleartextTraffic` como texto suelto. *No causa el fallo de red* (dart:io no pasa por la política de cleartext), pero se corrige | `AndroidManifest.xml:6-7` |

### APIs verificadas (sin dependencias nuevas)
`webSocketHandler(..., pingInterval:)` en `shelf_web_socket 1.0.4` · `IOWebSocketChannel.connect(url, {pingInterval, connectTimeout})` y `Future<void> get ready` en `web_socket_channel 2.4.0` · `connectedDisplaysChangedStream`, `getDisplays({category})` y `DISPLAY_CATEGORY_PRESENTATION` en `flutter_presentation_display 2.0.6`.

### Restricciones del plugin (leídas en su Kotlin)
- El entrypoint Dart **debe** llamarse `secondaryDisplayMain`.
- `showPresentation` **no desmonta** la `Presentation` anterior → hay que `hideSecondaryDisplay()` antes de re-mostrar tras una pérdida.
- `hidePresentation` **ignora** el `displayId`.
- El engine secundario queda cacheado en `FlutterEngineCache` (tag `presentation_scoreboard`) de forma permanente → **no se ve con hot reload/restart**; hay que `adb shell am force-stop com.techsolutions.basquetball.dev`.
- El engine secundario es un **isolate aparte**: no comparte `ProviderScope` ni memoria. Solo se comunica por WebSocket a loopback.

---

# ETAPA 0 — Documento de seguimiento y manifest · commit: `______`

- [x] **0.1 Crear `docs/PLAN_PANTALLA_EXTERNA.md`**
  Este archivo. Es el documento vivo que se marca y se edita.

- [x] **0.2 Corregir `android/app/src/main/AndroidManifest.xml`** *(defecto 12)*
  Líneas 6-7. Mover `android:usesCleartextTraffic="true"` **dentro** de la lista de atributos de
  `<application` y dejar un solo `>` al final:
  ```xml
  <application
      android:label="Van Ball"
      android:name="${applicationName}"
      android:usesCleartextTraffic="true"
      android:icon="@mipmap/ic_launcher">
  ```
  **No** añadir permisos: `ACCESS_WIFI_STATE`/`ACCESS_NETWORK_STATE` ya entran por merge del manifest de `network_info_plus`.

**Verificación:** `flutter build apk --debug` compila; `aapt dump badging` no muestra atributos huérfanos.

---

# ETAPA 1 — Detener el congelamiento y desbloquear al cliente

Tres bloques independientes, tres commits separados. **Entregable como APK al cliente antes de seguir.**

> **Estado: código completo.** `flutter analyze lib/` → 0 errores (quedan 5 *info* preexistentes ajenos
> a este trabajo). `flutter test test/scoreboard/` → **18/18 pasan**. `flutter build apk --debug` → OK.
> Falta la validación en dispositivo con el dongle real (ver cada bloque).

## 1.0 Cliente WebSocket resiliente *(defectos 0, 8)* — PRIMERO · commit: `______`

- [x] **1.0.1 Crear `lib/core/scoreboard/resilient_ws_client.dart`**

  Clase nueva. Es la pieza que mata la bomba exponencial y elimina la duplicación de cliente WS.

  ```dart
  class ResilientWsClient {
    ResilientWsClient({required List<Uri> endpoints});
    Stream<ScoreboardFeedEvent> get events;   // broadcast
    void start();
    Future<void> dispose();
  }
  ```

  Campos privados: `_channel`, `StreamSubscription? _sub`, `Timer? _retryTimer`,
  `bool _connecting`, `bool _disposed`, `int _attempt`, `int _endpointIndex`.

  **Reglas no negociables** (cada una corresponde a un fallo real del código actual):
  1. **Single-flight** — `_connect()` retorna de inmediato si `_connecting || _disposed`.
  2. **Reintento idempotente** — `_scheduleRetry()` hace `_retryTimer?.cancel()` **antes** de programar.
     Un intento fallido programa **exactamente uno**, vengan `onDone` y `onError` juntos o no.
  3. **`cancelOnError: true`** en el `listen`.
  4. **Limpieza previa** — antes de cada intento: `await _sub?.cancel(); _sub = null;`
     `await _channel?.sink.close(); _channel = null;`
  5. **Conexión con timeout real:**
     ```dart
     final ch = IOWebSocketChannel.connect(uri,
         connectTimeout: const Duration(seconds: 5),
         pingInterval: const Duration(seconds: 10));
     await ch.ready;   // dentro de try/catch → el fallo se detecta en 5 s, no en 120
     ```
  6. **Backoff** `1s → 2s → 4s → 8s`, tope 8 s, jitter ±20 %. `_attempt = 0` al conectar con éxito.
  7. **Rotación de endpoints** — cada reintento avanza `_endpointIndex` circularmente. Así el isolate
     secundario encuentra el puerto de fallback (`:8080`, `:8081`, `:8082`) sin memoria compartida.
  8. `dispose()` pone `_disposed = true`, cancela timer y suscripción, cierra el canal y el `StreamController`.

- [x] **1.0.2 Sustituir el cliente de `lib/main.dart`** *(defecto 0)*
  En `_AnycastDisplayScreenState`: borrados `_connectToLocalhost()` y `_retryConnection()`; ahora usa
  `ResilientWsClient` sobre `ScoreboardEndpoint.loopbackCandidates()`. Provisional en esta etapa — el
  archivo se extrae entero en la 4.2.

- [x] **1.0.3 Adelanto de 2.4: `lib/core/scoreboard/scoreboard_endpoint.dart`**
  Hacía falta ya en 1.0.2 para los candidatos de loopback. Ver Etapa 2.4 (marcada como hecha).

**Verificación:** `test/scoreboard/resilient_ws_client_test.dart` — 4 tests, **pasan**.
- Puerto cerrado durante 6 s → **4 intentos** (lineal). El código anterior superaba los 1000.
- Caída del socket desde el servidor → **exactamente 1** evento de desconexión (`onDone` + `onError` ya no duplican).
- Entrega de mensajes y `dispose()` que detiene los reintentos: OK.

Pendiente en dispositivo: `flutter run --profile` + DevTools Memory → curva plana con el HDMI conectado
y sin partido abierto.

## 1.1 Servidor WebSocket *(defectos 5, 6, 10, 11)* · commit: `______`

- [x] **1.1.1 Reescribir `lib/core/network/websocket_server.dart`** (42 → ~185 líneas)

  API objetivo de `LocalWebSocketServer`:
  ```dart
  int? get port;   int get clientCount;   bool get isRunning;
  Stream<PublisherStatus> get status;
  Future<int> startServer();      // devuelve el puerto efectivo
  void broadcast(String message);
  void clearLastPayload();
  Future<void> stopServer();
  ```

  - **Depurar clientes** *(defecto 5)* — dentro de `webSocketHandler`, registrar:
    ```dart
    ws.stream.listen((_) {},
        onDone: () => _remove(ws), onError: (_) => _remove(ws), cancelOnError: true);
    ```
    Sin este `listen` el canal nunca emite `onDone` y la lista crece para siempre.
  - **`broadcast` a prueba de fallos** — el arreglo del congelamiento del marcador:
    ```dart
    void broadcast(String message) {
      _lastPayload = message;
      for (final c in List.of(_clients)) {   // copia: permite mutar durante el bucle
        try { c.sink.add(message); }         // try POR CLIENTE, nunca envolviendo el for
        catch (_) { _remove(c); }
      }
    }
    ```
  - **`pingInterval: const Duration(seconds: 10)`** en `webSocketHandler` *(defecto 6)*.
  - **`shared: false`** + fallback sobre `[8080, 8081, 8082]` capturando `SocketException`; guardar el
    puerto efectivo en `_port` *(defecto 10)*.
  - **`clearLastPayload()`** deja `_lastPayload = null`; si es `null` no se envía nada al conectar *(defecto 11)*.

**Verificación:** `test/scoreboard/websocket_server_test.dart` — 4 tests, **pasan**.
- 3 clientes, se cierra el primero, `broadcast` → los otros dos reciben y `clientCount` baja a 2.
- Cliente que conecta tarde recibe el último marcador; `clearLastPayload()` lo suprime.
- `startServer()` idempotente y concurrente-seguro, devuelve siempre el mismo puerto.

## 1.2 Máquina de estados de pantalla externa *(defectos 1, 2, 3, 4)* · commit: `______`

- [x] **1.2.1 Reescribir `lib/core/service/external_display_service.dart`** (68 → ~270 líneas)

  Conservar el nombre de clase en esta etapa para no tocar los 4 call sites; el rename a
  `ExternalDisplayController` va en la 3.1.

  ```dart
  enum ExternalDisplayStatus { idle, probing, showing, lost, disabled }

  Stream<ExternalDisplayStatus> get statusStream;
  ExternalDisplayStatus get status;
  Future<void> start();                      // idempotente, una vez en el bootstrap
  Future<void> requestShow({bool force});
  Future<void> disable();   Future<void> enable();
  Future<void> dispose();
  ```

  Métodos privados: `_reconcile()`, `_onDisplayEvent(int?)`, `_findPresentationDisplay()`, `_enqueue(Future Function())`.

  1. `start()` se suscribe a `_manager.connectedDisplaysChangedStream` — el único mecanismo que cubre el AnyCast que enlaza 20 s tarde *(defecto 1)*.
  2. `_findPresentationDisplay()` usa `getDisplays(category: DISPLAY_CATEGORY_PRESENTATION)` y toma
     `.first` — **nunca `displays[1]`**. Esa lista ya excluye el display integrado y los virtuales *(defecto 3)*.
  3. Sustituir el guard `if (_isShowing) return` por `_reconcile()`, que compara el estado **deseado**
     contra la lista **real** de displays de categoría PRESENTATION. Mata el desincronizado permanente *(defecto 2)*.
  4. Evento `0` (removed) → estado `lost` + `hideSecondaryDisplay()`. **Obligatorio**: el nativo no
     desmonta la `Presentation` anterior en un re-show y quedaría una instancia huérfana.
  5. Evento `1` (added) → debounce 800 ms + reintentos `[0, 1s, 3s, 6s]`: el AnyCast reporta el display
     antes de que sea usable y `showSecondaryDisplay` falla con `DISPLAY_NOT_FOUND`.
  6. `Timer.periodic(10s)` de reconciliación mientras `status` no sea `showing` ni `disabled`; se cancela
     al llegar a `showing` *(defecto 4)*.
  7. `_operationInProgress` pasa de **descartar** a **encolar** (cadena de `Future`), para que un evento
     no se pierda por llegar durante otra operación.

- [x] **1.2.2 Actualizar call sites**
  - `lib/main.dart` → `ExternalDisplayService.instance.start()` (quitado el `postFrameCallback`)
  - `lib/main.dart` (`resumed`) → `requestShow()`
  - `lib/ui/match_control_screen.dart` → llamada **eliminada** (el servicio ya es autónomo); import fuera
  - `lib/ui/home_menu_screen.dart` → `disable()`

- [x] **1.2.3 Añadido "Reconectar pantalla" al menú admin**
  No estaba en el plan original: `disable()` ahora es **permanente** hasta reactivar (antes
  `hideScoreboard()` se deshacía solo al entrar a un partido). Sin este ítem el usuario quedaba
  atrapado sin forma de volver a encender la TV. Llama a `requestShow(force: true)` y avisa según el
  `ExternalDisplayStatus` resultante.

**Verificación (emulador, sin dongle) — PENDIENTE en dispositivo:**
`adb shell settings put global overlay_display_devices "1280x720/213"` crea un display secundario y
dispara `onDisplayAdded`; `... none` dispara `onDisplayRemoved`. **Ciclar 3 veces** es la prueba del
defecto 2: antes el marcador no volvía tras el primer ciclo. El `debugPrint` de
`ExternalDisplay: estado -> …` permite seguir la máquina de estados en el logcat.

## 1.3 Pantalla de cliente por IP *(defecto 7)* · commit: `______`

- [x] **1.3.1 `lib/ui/client_scoreboard_screen.dart` — arreglar el teclado**
  ```dart
  keyboardType: TextInputType.text,
  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.:]'))],
  ```
  `numberWithOptions(decimal: true)` **no** garantiza el `:`; el filtro sobre teclado de texto funciona en todos los IMEs.

- [x] **1.3.2 Migrar `_connectToServer()` a `ResilientWsClient`**
  Tres vistas explícitas: formulario → espera → marcador. Al perder la red, banner *"Sin señal.
  Reconectando en Ns"* **sobre** el `TvScoreboardWidget`, sin volver al formulario ni borrar el
  marcador de la pared. Solo la desconexión manual (`_unlink`) vuelve al formulario. El cliente se
  cancela en `dispose()`. Validación de IP delegada a `ScoreboardEndpoint`.

**Verificación:** `test/scoreboard/scoreboard_endpoint_test.dart` — 10 tests, **pasan** (IP con y sin
puerto, `ws://` completa, rechazo de `999.1.1.1` / puerto 99999 / `http://`, candidatos por puerto).
Pendiente en dispositivo: emulador con Gboard → el teclado ofrece `.` y `:`; apuntar a `10.255.255.1`
(no enrutable) → falla en ~5 s con banner de reintento, no se cuelga.

---

# ETAPA 2 — DTO único + abstracción de transporte · commit: `______`

Paquete nuevo `lib/core/scoreboard/`. Elimina el JSON escrito a mano en 3 archivos.

- [x] **2.1 Crear `lib/core/scoreboard/scoreboard_payload.dart`**
  ```dart
  @immutable
  class ScoreboardPayload {
    static const int schemaVersion = 1;
    final MatchState state;
    final String teamAName, teamBName;
    final int teamAFouls, teamBFouls;
    final bool isFinished;

    Map<String, dynamic> toJson();
    String encode();
    factory ScoreboardPayload.fromJson(Map<String, dynamic> j);
    static ScoreboardPayload? tryDecode(String raw);   // null si es basura
  }
  ```
  `fromJson` acepta la forma actual (`{state:…, teamAName:…}`) **y** la legacy (mapa plano = solo
  `MatchState`), igual que hacen hoy los dos receptores → permite desplegar emisor y receptor por separado.

- [x] **2.2 Extraer `getTeamFouls` a función pura**
  `lib/logic/match_game_controller.dart:294` solo lee `state.scoreLog` y `state.currentPeriod`.
  Mover a `int teamFoulsOf(MatchState s, String teamId)` y dejar `MatchGameController.getTeamFouls`
  delegando. Elimina la dependencia de la difusión hacia un notifier que puede estar **destruido** tras
  `ref.invalidate(matchGameProvider)` (`fixture_list_screen.dart:952`, `match_control_screen.dart:1303`).

- [x] **2.3 Crear `lib/core/scoreboard/scoreboard_transport.dart`** — interfaces (DIP + OCP)
  ```dart
  abstract interface class ScoreboardPublisher {
    Future<void> start();
    void publish(ScoreboardPayload payload);
    void clear();
    Future<void> stop();
    Stream<PublisherStatus> get status;      // {running, port, clientCount}
  }

  sealed class ScoreboardFeedEvent {}
  class FeedConnecting   extends ScoreboardFeedEvent { final int attempt; }
  class FeedData         extends ScoreboardFeedEvent { final ScoreboardPayload payload; }
  class FeedWaiting      extends ScoreboardFeedEvent {}
  class FeedDisconnected extends ScoreboardFeedEvent { final Object? error; final Duration retryIn; }

  abstract interface class ScoreboardSubscriber {
    Stream<ScoreboardFeedEvent> subscribe(Uri endpoint);
    Future<void> dispose();
  }
  ```
  Añadir otro medio (BLE, Nearby, MQTT) = una clase nueva, cero cambios en UI.

- [x] **2.4 Crear `lib/core/scoreboard/scoreboard_endpoint.dart`** *(defecto 10)* — adelantado en Etapa 1.0.3
  ```dart
  static const List<int> candidatePorts = [8080, 8081, 8082];
  static const String loopbackHost = '127.0.0.1';
  static Uri? parseUserInput(String raw);       // "192.168.1.5" | "…:8081" | "ws://…"
  static String? validationError(String raw);
  static Iterable<Uri> loopbackCandidates();
  ```

- [x] **2.5 Crear `ws_scoreboard_publisher.dart` y `ws_scoreboard_subscriber.dart`**
  El publisher envuelve el `LocalWebSocketServer` de 1.1 detrás de la interfaz; el subscriber envuelve
  el `ResilientWsClient` de 1.0.

- [x] **2.6 Reemplazar los 3 JSON a mano** por `ScoreboardPayload`
  `match_control_screen.dart:146-152` · `main.dart:125-135` · `client_scoreboard_screen.dart:47-58`

**Verificación:** `test/scoreboard/scoreboard_payload_test.dart` — 6 tests, **pasan**: round-trip
completo, cálculo de faltas del período en curso (ignora períodos previos, el otro equipo y las
canastas), forma legacy, `tryDecode` con 5 entradas basura, y versión de esquema en el JSON.

> **Nota de diseño (cambio respecto al plan):** los eventos de transporte y los de dominio se separaron
> en dos capas en vez de una. `ResilientWsClient` emite `WsClientEvent` (solo sockets, sin saber nada
> del marcador) y `WebSocketScoreboardSubscriber` los traduce a `ScoreboardFeedEvent`. Así el cliente WS
> es reutilizable para cualquier payload y el mapeo vive en un único sitio.

---

# ETAPA 3 — Sacar servidor y difusión de `MatchControlScreen` *(defectos 0b, 9, 11)* · commit: `______`

Corrección de SRP/DIP: hoy un widget de 1829 líneas posee la infraestructura.

- [x] **3.1 Crear `lib/core/scoreboard/scoreboard_providers.dart`**
  ```dart
  final scoreboardPublisherProvider = Provider<ScoreboardPublisher>((ref) {
    final p = WebSocketScoreboardPublisher()..start();
    ref.onDispose(p.stop);
    return p;
  });

  final publisherStatusProvider = StreamProvider<PublisherStatus>(
      (ref) => ref.watch(scoreboardPublisherProvider).status);

  final localIpProvider = FutureProvider<String?>((ref) => NetworkInfo().getWifiIP());

  /// Metadatos que MatchState no lleva. La pantalla del partido solo ESCRIBE aquí.
  final scoreboardMetaProvider = StateProvider<ScoreboardMeta?>((ref) => null);

  final scoreboardBroadcasterProvider = Provider<ScoreboardBroadcaster>((ref) {
    final b = ScoreboardBroadcaster(ref.watch(scoreboardPublisherProvider));
    ref.listen<MatchState>(matchGameProvider, (_, n) => b.onState(n), fireImmediately: true);
    ref.listen<ScoreboardMeta?>(scoreboardMetaProvider, (_, m) => b.onMeta(m), fireImmediately: true);
    ref.onDispose(b.dispose);
    return b;
  });

  final externalDisplayControllerProvider = Provider<ExternalDisplayController>((ref) {
    final c = ExternalDisplayController(PresentationDisplayGateway())..start();
    ref.onDispose(c.dispose);
    return c;
  });
  ```
  Sigue el patrón de service locator ya establecido en `lib/core/di/dependency_injection.dart`
  (inyección por constructor sobre `Provider`). **No** hace falta `keepAlive`: en Riverpod 2.6 un
  `Provider` sin `.autoDispose` vive tanto como el `ProviderContainer`. El problema es que es **lazy**.

- [x] **3.2 Crear `lib/ui/app_bootstrap.dart`**
  ```dart
  class AppBootstrap extends ConsumerWidget {
    final Widget child;
    @override
    Widget build(BuildContext context, WidgetRef ref) {
      ref.watch(scoreboardBroadcasterProvider);
      ref.watch(externalDisplayControllerProvider);
      return child;
    }
  }
  ```
  En `lib/main.dart:13`: `ProviderScope(child: AppBootstrap(child: MyApp()))`.
  **Efecto directo:** el servidor arranca al abrir la app → la IP está disponible desde el menú
  *(defecto 9)* y el receptor externo ya nunca corre contra un servidor inexistente *(defecto 0b)*.

- [x] **3.3 Crear `lib/core/scoreboard/scoreboard_broadcaster.dart`**
  ```dart
  class ScoreboardBroadcaster {
    ScoreboardBroadcaster(this._publisher);
    void onState(MatchState s);
    void onMeta(ScoreboardMeta? m);   // m == null → _publisher.clear()
    void dispose();
  }
  ```
  - Compone `ScoreboardPayload` desde `MatchState` + `ScoreboardMeta` + `teamFoulsOf(...)`.
  - **Coalescing de 50 ms** (timer de un disparo reprogramable): las ráfagas de cambios no inundan a los
    clientes; el tick del reloj (1/s) pasa igual.
  - `onMeta(null)` → `clear()`: al hacer `ref.invalidate(matchGameProvider)` se pone también
    `scoreboardMetaProvider` a `null` → *defecto 11* resuelto en una línea.

- [x] **3.4 Adelgazar `lib/ui/match_control_screen.dart`** (~40 líneas menos)
  - **Borrar:** líneas 98-99 (`startServer`, `showScoreboard`), campo `_localIp` (89) y `_fetchLocalIp`
    (168-180), `_broadcastFastUpdate` (141-157), la llamada en `build` (233), e imports de
    `websocket_server.dart`, `network_info_plus`, `dart:convert`, `external_display_service.dart`.
  - **Añadir** en `initState`:
    ```dart
    ref.read(scoreboardMetaProvider.notifier).state = ScoreboardMeta(
        teamAName: widget.teamAName, teamBName: widget.teamBName, matchId: widget.matchId);
    ```
    y actualizar con `isFinished: true` cerca de la línea 1292.
  - El chip de IP del AppBar (línea 305) pasa a `Consumer` sobre `localIpProvider` +
    `publisherStatusProvider`: IP, puerto y nº de clientes conectados.

**Verificación:** `test/scoreboard/scoreboard_broadcaster_test.dart` — 5 tests, **pasan**: no difunde sin
partido abierto, difunde al declararlo, **agrupa 10 cambios en una sola emisión** (coalescing) quedándose
con el último estado, `onMeta(null)` limpia y bloquea emisiones posteriores, y `dispose()` cancela lo
pendiente.

Además de `match_control_screen.dart` se quitaron `_broadcastFastUpdate`, `_fetchLocalIp`, el campo
`_localIp`, el arranque del servidor y 2 imports; el chip de IP pasó a `_ScoreboardNetworkChip`
(`Consumer` sobre `localIpProvider` + `publisherStatusProvider`, muestra IP, puerto y nº de pantallas).
También se limpia `scoreboardMetaProvider` al finalizar el partido y al abandonarlo desde
`fixture_list_screen.dart`.

Pendiente en dispositivo: abrir la app **sin** entrar a un partido → la IP y el puerto se ven en
«Estado del marcador» y una tablet puede enlazar antes de empezar.

---

# ETAPA 4 — Receptor compartido · commit: `______`

Elimina la duplicación de cliente + parseo + render entre los dos receptores.

- [x] **4.1 Crear `lib/ui/widgets/scoreboard_feed_view.dart`**
  ```dart
  final scoreboardFeedProvider =
      StreamProvider.autoDispose.family<ScoreboardFeedEvent, Uri>((ref, uri) {
    final sub = WebSocketScoreboardSubscriber();
    ref.onDispose(sub.dispose);
    return sub.subscribe(uri);
  });

  class ScoreboardFeedView extends ConsumerWidget {
    final Uri endpoint;
    // pinta TvScoreboardWidget con el último payload conocido;
    // superpone banner "Conectando / Reconectando en Ns" SIN borrar el marcador.
  }
  ```
  `autoDispose` cierra el socket al salir de la pantalla, sin `dispose` manual.

- [x] **4.2 Crear `lib/ui/secondary_display_app.dart`**
  Extraer `AnycastDisplayScreen` de `lib/main.dart:97-184`. `secondaryDisplayMain` queda en 4 líneas:
  `runApp(ProviderScope(child: SecondaryDisplayApp()))`, con **su propio `ProviderScope`** (isolate
  aparte). Documentar en el docstring que el nombre del entrypoint está hardcodeado en el plugin.

- [x] **4.3 Simplificar `lib/ui/client_scoreboard_screen.dart`** (204 → ~120 líneas)
  Pasa a `ConsumerStatefulWidget`: solo formulario/descubrimiento + `ScoreboardFeedView`.
  Sin `setState` de datos ni parseo propio.

> **Corrección sobre el plan (importante):** `secondaryDisplayMain` **NO** se movió a
> `secondary_display_app.dart`. El plugin lo invoca con
> `DartExecutor.DartEntrypoint(path, "secondaryDisplayMain")` **sin URI de librería**, así que el motor
> lo resuelve en la librería raíz: moverlo (o solo reexportarlo con `export`) dejaría la TV en negro.
> Se queda en `lib/main.dart` como función de 3 líneas que hace `runApp(SecondaryDisplayApp())`.

**Verificación:** `flutter analyze` limpio y APK compila. Pendiente en dispositivo: dos emuladores,
cliente apuntando a `10.0.2.2` o a la IP LAN; apagar y encender el servidor → aparece el banner de
reconexión y el marcador vuelve solo. La pantalla externa usa `showConnectionBanner: false` para no
mostrar avisos de red al público de la cancha.

---

# ETAPA 5 — Descubrimiento automático en LAN + diagnóstico · commit: `______`

- [x] **5.1 Crear `lib/core/scoreboard/lan_scoreboard_discovery.dart`** (sin dependencias nuevas)
  ```dart
  class LanScoreboardDiscovery {
    Stream<DiscoveredScoreboard> scan({Duration timeout = const Duration(seconds: 6)});
  }
  ```
  - Deriva el `/24` de `NetworkInfo().getWifiIP()` (ya en uso en `match_control_screen.dart:171`).
  - `Socket.connect(host, port, timeout: 300ms)` sobre `.1–.254` × `candidatePorts`.
  - **Semáforo de 32 sockets concurrentes** — imprescindible: 762 conexiones en paralelo reproducirían
    exactamente el congelamiento que estamos arreglando.
  - **Verificación real de cada candidato**: hacer el handshake WS y aceptar solo si llega un payload
    decodificable por `ScoreboardPayload.tryDecode`. Evita falsos positivos de otro servicio en 8080.
  - Emite resultados a medida que llegan (`Stream`), cancelable, se aborta en `dispose`.

- [x] **5.2 UI de descubrimiento en `client_scoreboard_screen.dart`**
  Botón *"Buscar marcador en la red"* → lista de dispositivos encontrados (IP + puerto), toque para
  enlazar. El campo manual se conserva como respaldo.

- [x] **5.3 Crear `lib/ui/scoreboard_server_screen.dart`**
  Pantalla de diagnóstico: IP, puerto efectivo, nº de clientes conectados, `ExternalDisplayStatus`, y
  botones *"Reintentar pantalla externa"* / *"Desconectar"*. Entrada nueva en el menú admin de
  `lib/ui/home_menu_screen.dart` junto a `'scoreboard'` y `'disconnect_display'`.

El escaneo es en dos fases: primero un `Socket.connect` barato (300 ms) para descartar hosts muertos,
y solo sobre los que responden se hace el handshake WS y se exige un `ScoreboardPayload` decodificable.
La lista de resultados deduplica por host (un mismo equipo puede responder en varios puertos candidatos).

**Verificación:** `flutter analyze` limpio y APK compila. Pendiente en dispositivo: discovery con el
servidor apagado → 0 resultados en ≤ 6 s **sin jank**; con el servidor encendido → aparece en < 3 s.
Comprobar en DevTools que los sockets concurrentes no pasan de 32.

---

## Prueba de aceptación end-to-end (con hardware, antes de entregar APK)

- [ ] App abierta 30 min con el AnyCast conectado y **sin** partido → sin congelamiento (defectos 0 y 0b).
- [ ] Partido completo con TV por HDMI/AnyCast + tablet por IP, marcador sincronizado de principio a fin.
- [ ] Desconectar y reconectar el dongle a mitad de un período → el marcador vuelve solo, sin reiniciar.
- [ ] Cortar el Wi-Fi de la tablet 30 s y restaurarlo → reconecta sola, sin volver al formulario de IP.
- [ ] Enlazar la tablet por descubrimiento, sin teclear la IP.
- [ ] Cerrar el partido y abrir otro → el cliente no ve el marcador del anterior.
