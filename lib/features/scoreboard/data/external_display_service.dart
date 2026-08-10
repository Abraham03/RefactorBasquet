import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_presentation_display/display.dart';
import 'package:flutter_presentation_display/flutter_presentation_display.dart';

/// Estado observable de la pantalla externa (HDMI o dongle AnyCast).
enum ExternalDisplayStatus {
  /// Aún no se ha sondeado.
  idle,

  /// Hay una pantalla candidata y se está intentando mostrar en ella.
  probing,

  /// El marcador está visible en la pantalla externa.
  showing,

  /// Había pantalla y se perdió; se reintenta en segundo plano.
  lost,

  /// El usuario apagó la función a mano. No se reintenta.
  disabled,
}

/// Gestiona la pantalla externa de forma independiente del ciclo de vida de
/// cualquier widget.
///
/// Diseño reactivo, no de disparo puntual: el dongle AnyCast puede tardar
/// 10-30 s en enlazar, mucho después de que la app arranque o de que se abra
/// el partido. Antes solo se sondeaba en tres momentos concretos y un
/// `bool _isShowing` decidía si actuar; cuando se desconectaba el cable, el
/// nativo desmontaba la `Presentation` pero el booleano seguía en `true`, así
/// que la pantalla no volvía nunca sin reiniciar la app.
///
/// Ahora la verdad es siempre el sondeo real de displays, y las transiciones
/// las dispara el `DisplayManager` de Android vía
/// [FlutterPresentationDisplay.connectedDisplaysChangedStream].
class ExternalDisplayService {
  /// El ciclo de vida lo gestiona `externalDisplayProvider`, que es el único
  /// que debe construirlo y arrancarlo.
  ///
  /// Antes era un singleton estático arrancado desde DOS sitios a la vez
  /// (`main.dart` y el propio provider), y ninguna prueba de widget podía
  /// sustituirlo: `MyApp.initState` llamaba al canal nativo y reventaba con
  /// `MissingPluginException` en el host de tests.
  ExternalDisplayService();

  static const String _routerName = 'presentation_scoreboard';

  /// El AnyCast anuncia el display antes de que sea usable; sin esta espera,
  /// `showSecondaryDisplay` falla con DISPLAY_NOT_FOUND.
  static const Duration _addedDebounce = Duration(milliseconds: 800);
  static const List<Duration> _showRetryDelays = [
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ];
  static const Duration _reconcileInterval = Duration(seconds: 10);

  final FlutterPresentationDisplay _manager = FlutterPresentationDisplay();
  final StreamController<ExternalDisplayStatus> _statusController =
      StreamController<ExternalDisplayStatus>.broadcast();

  StreamSubscription<int?>? _displayEventSub;
  Timer? _debounceTimer;
  Timer? _reconcileTimer;

  /// Serializa las operaciones sobre el canal nativo. Encola en vez de
  /// descartar: antes, un evento que llegaba durante otra operación se perdía.
  Future<void> _queue = Future<void>.value();

  ExternalDisplayStatus _status = ExternalDisplayStatus.idle;
  bool _started = false;
  bool _disposed = false;

  /// Lo que el usuario quiere. `false` solo cuando apaga la función a mano.
  bool _desired = true;

  int? _shownDisplayId;

  ExternalDisplayStatus get status => _status;
  Stream<ExternalDisplayStatus> get statusStream => _statusController.stream;
  bool get isShowing => _status == ExternalDisplayStatus.showing;

  /// Arranca la vigilancia. Idempotente: llamar una vez al inicio de la app.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    _displayEventSub = _manager.connectedDisplaysChangedStream.listen(
      _onDisplayEvent,
      onError: (Object e) => debugPrint('ExternalDisplay: evento erróneo: $e'),
    );

    await _enqueue(_reconcile);
    _ensureReconcileTimer();
  }

  /// Sondeo manual (arranque, vuelta de segundo plano, botón "reintentar").
  Future<void> requestShow({bool force = false}) async {
    if (_disposed) return;
    if (_status == ExternalDisplayStatus.disabled && !force) return;
    if (force) _desired = true;
    await _enqueue(_reconcile);
    _ensureReconcileTimer();
  }

  /// Apaga el marcador externo a petición del usuario. No se reintenta hasta
  /// un [enable] o un [requestShow] con `force`.
  Future<void> disable() async {
    if (_disposed) return;
    _desired = false;
    _cancelTimers();
    await _enqueue(() async {
      await _hide();
      _setStatus(ExternalDisplayStatus.disabled);
    });
  }

  Future<void> enable() async {
    if (_disposed) return;
    _desired = true;
    _setStatus(ExternalDisplayStatus.idle);
    await _enqueue(_reconcile);
    _ensureReconcileTimer();
  }

  // --- Eventos del DisplayManager ------------------------------------------

  void _onDisplayEvent(int? event) {
    if (_disposed || !_desired) return;

    if (event == 0) {
      // Pantalla retirada. Hay que desmontar explícitamente: el plugin nativo
      // no descarta la Presentation anterior al volver a mostrar, y quedaría
      // una instancia huérfana enganchada al display que ya no existe.
      _debounceTimer?.cancel();
      _enqueue(() async {
        await _hide();
        _setStatus(ExternalDisplayStatus.lost);
      });
      _ensureReconcileTimer();
      return;
    }

    // Pantalla añadida: esperar a que sea usable antes de intentar.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_addedDebounce, () {
      _enqueue(_reconcile);
    });
  }

  // --- Reconciliación -------------------------------------------------------

  /// Compara el estado deseado con la realidad del sistema y actúa.
  /// Nunca decide en base a un booleano cacheado.
  Future<void> _reconcile() async {
    if (_disposed) return;
    if (!_desired) {
      _setStatus(ExternalDisplayStatus.disabled);
      return;
    }

    final display = await _findPresentationDisplay();
    if (display == null) {
      if (_status == ExternalDisplayStatus.showing) {
        // Estaba visible y el display desapareció sin avisar.
        await _hide();
        _setStatus(ExternalDisplayStatus.lost);
      } else if (_status != ExternalDisplayStatus.lost) {
        _setStatus(ExternalDisplayStatus.idle);
      }
      return;
    }

    final displayId = display.displayId;
    if (displayId == null) return;

    // Ya visible en esa misma pantalla: nada que hacer.
    if (_status == ExternalDisplayStatus.showing && _shownDisplayId == displayId) {
      return;
    }

    _setStatus(ExternalDisplayStatus.probing);

    // Si veníamos de una pérdida o de otra pantalla, desmontar primero.
    if (_shownDisplayId != null && _shownDisplayId != displayId) {
      await _hide();
    }

    for (final delay in _showRetryDelays) {
      if (_disposed || !_desired) return;
      if (delay > Duration.zero) await Future<void>.delayed(delay);

      try {
        final ok = await _manager.showSecondaryDisplay(
          displayId: displayId,
          routerName: _routerName,
        );
        if (ok ?? false) {
          _shownDisplayId = displayId;
          _setStatus(ExternalDisplayStatus.showing);
          _cancelReconcileTimer();
          debugPrint('ExternalDisplay: marcador visible en $displayId');
          return;
        }
      } catch (e) {
        debugPrint('ExternalDisplay: intento fallido en $displayId: $e');
      }
    }

    _setStatus(ExternalDisplayStatus.lost);
  }

  /// Solo displays de categoría PRESENTATION.
  ///
  /// Antes se tomaba `displays[1]` de la lista sin filtrar, que incluye
  /// displays virtuales (grabación de pantalla, overlays de depuración) y no
  /// garantiza el orden. Esta lista ya excluye el display integrado, así que
  /// el candidato correcto es el primero.
  Future<Display?> _findPresentationDisplay() async {
    try {
      final displays = await _manager.getDisplays(
        category: DISPLAY_CATEGORY_PRESENTATION,
      );
      if (displays == null || displays.isEmpty) return null;
      return displays.first;
    } catch (e) {
      debugPrint('ExternalDisplay: no se pudieron listar displays: $e');
      return null;
    }
  }

  Future<void> _hide() async {
    final displayId = _shownDisplayId;
    _shownDisplayId = null;
    if (displayId == null) return;
    try {
      await _manager.hideSecondaryDisplay(displayId: displayId);
    } catch (e) {
      debugPrint('ExternalDisplay: error al ocultar: $e');
    }
  }

  // --- Infraestructura ------------------------------------------------------

  /// Reintento de fondo mientras no esté visible: cubre el caso del dongle que
  /// enlaza tarde sin emitir evento, o cuyo evento se perdió.
  void _ensureReconcileTimer() {
    if (_disposed || _reconcileTimer != null) return;
    if (_status == ExternalDisplayStatus.showing ||
        _status == ExternalDisplayStatus.disabled) {
      return;
    }
    _reconcileTimer = Timer.periodic(_reconcileInterval, (_) {
      if (_status == ExternalDisplayStatus.showing ||
          _status == ExternalDisplayStatus.disabled) {
        _cancelReconcileTimer();
        return;
      }
      _enqueue(_reconcile);
    });
  }

  void _cancelReconcileTimer() {
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _cancelReconcileTimer();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await operation();
      } catch (e) {
        debugPrint('ExternalDisplay: operación fallida: $e');
      }
    });
    return _queue;
  }

  void _setStatus(ExternalDisplayStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
    debugPrint('ExternalDisplay: estado -> ${next.name}');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelTimers();
    await _displayEventSub?.cancel();
    _displayEventSub = null;
    await _statusController.close();
  }
}
