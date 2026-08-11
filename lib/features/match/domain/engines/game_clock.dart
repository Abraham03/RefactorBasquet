import 'dart:async';

import 'package:myapp/features/match/domain/entities/match_state.dart';

/// Qué debe ocurrir tras avanzar el reloj un segundo.
///
/// El motor decide; el controller ejecuta los efectos (persistir, parar). Así
/// las reglas del reloj se prueban sin `Timer` y sin base de datos.
class ClockTick {
  const ClockTick({
    required this.timeLeft,
    required this.expired,
    required this.shouldAutoBurn,
    required this.shouldPersist,
  });

  /// Tiempo restante después del tick.
  final Duration timeLeft;

  /// Se acabó el período: hay que parar el reloj.
  final bool expired;

  /// Se cruzó el minuto 2:00 del último período: toca quemar los tiempos
  /// muertos de la segunda mitad que no se hayan usado.
  final bool shouldAutoBurn;

  /// Toca escribir el reloj en la base de datos.
  final bool shouldPersist;
}

/// Las reglas del reloj de juego.
///
/// Vivían dentro del callback de `Timer.periodic` en el controller, así que
/// para probarlas había que esperar segundos reales.
abstract final class GameClockRules {
  /// Período en el que aplica el "clutch time".
  static const int lastPeriod = 4;

  /// A falta de este tiempo en el último período se queman los tiempos
  /// muertos no usados de la segunda mitad.
  static const Duration autoBurnAt = Duration(minutes: 2);

  /// El reloj se persiste cada tantos segundos, no en cada tick: escribir en
  /// la base de datos una vez por segundo durante 40 minutos es innecesario.
  static const int persistEverySeconds = 5;

  /// Calcula el efecto de avanzar un segundo desde [state].
  static ClockTick advance(MatchState state) {
    if (state.timeLeft.inSeconds <= 0) {
      return const ClockTick(
        timeLeft: Duration.zero,
        expired: true,
        shouldAutoBurn: false,
        // Al agotarse SÍ se persiste, aunque no toque por cadencia: es el
        // final del período y hay que dejarlo guardado.
        shouldPersist: true,
      );
    }

    final next = state.timeLeft - const Duration(seconds: 1);

    return ClockTick(
      timeLeft: next,
      expired: false,
      // Se compara por igualdad, no por "menor que": el auto-burn debe
      // dispararse UNA vez, justo al cruzar el umbral.
      shouldAutoBurn:
          state.currentPeriod == lastPeriod &&
          next.inSeconds == autoBurnAt.inSeconds,
      shouldPersist: next.inSeconds % persistEverySeconds == 0,
    );
  }

  /// Quema un tiempo muerto de la segunda mitad a cada equipo que no haya
  /// gastado ninguno.
  ///
  /// Devuelve `null` si no había nada que quemar, para que el llamador no
  /// guarde en el historial de deshacer un paso que no cambió nada.
  /// ¿El partido ya pasó el momento de la quema automática?
  ///
  /// Sirve para RESTAURAR: la quema no deja evento en `gameEvents` ni columna
  /// propia —solo toca el estado en memoria—, así que al reabrir un partido
  /// terminado había que recalcularla o el acta salía sin ella.
  ///
  /// Cierto en el último período a partir del umbral, y en cualquier prórroga
  /// (para llegar a prórroga hubo que atravesar el final del cuarto período).
  static bool autoBurnAlreadyHappened(MatchState state) =>
      state.currentPeriod > lastPeriod ||
      (state.currentPeriod == lastPeriod && state.timeLeft <= autoBurnAt);

  /// Quema los tiempos muertos sin usar de un partido que **se acaba de
  /// cerrar**, o `null` si no había nada que quemar.
  ///
  /// **No mira el reloj, y es a propósito.** [autoBurnAlreadyHappened] sirve
  /// para un partido en curso: ahí el umbral de los dos minutos es la regla.
  /// Pero al cerrar, el equipo que no gastó su tiempo muerto de la segunda
  /// mitad lo ha perdido igual, porque ya no queda ocasión de pedirlo.
  ///
  /// La diferencia importa porque el reloj guardado **no siempre llega a
  /// 00:00**: `setTime` y `adjustTime` no persisten, y `setPeriod` reinicia a
  /// 10:00. Un acta cerrada tras ajustar el tiempo a mano se quedaba sin la
  /// marca de quema aunque el partido hubiera terminado.
  static MatchState? burnUnusedAtEnd(MatchState state) =>
      state.currentPeriod >= lastPeriod ? applyAutoBurn(state) : null;

  static MatchState? applyAutoBurn(MatchState state) {
    final listA = List<String>.from(state.teamATimeouts2);
    final listB = List<String>.from(state.teamBTimeouts2);

    var changed = false;
    if (listA.isEmpty) {
      listA.add('X');
      changed = true;
    }
    if (listB.isEmpty) {
      listB.add('X');
      changed = true;
    }

    if (!changed) return null;
    return state.copyWith(teamATimeouts2: listA, teamBTimeouts2: listB);
  }
}

/// El reloj en sí: un `Timer` periódico con la cadencia inyectable.
///
/// Se separa de las reglas para poder acelerarlo en los tests. Antes el
/// `Timer` era un campo suelto del controller (`Timer? _timer`), fuera del
/// estado y sin forma de sustituirlo.
class GameClock {
  GameClock({this.interval = const Duration(seconds: 1)});

  final Duration interval;
  Timer? _timer;

  bool get isRunning => _timer != null;

  /// Arranca el reloj. Reiniciar uno ya en marcha es seguro: se cancela el
  /// anterior para no dejar dos temporizadores compitiendo.
  void start(void Function() onTick) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
