import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/match/domain/engines/game_clock.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';

/// Los tres cupos de tiempos muertos de un partido.
///
/// No son intercambiables: lo que no se gasta en la primera mitad **no se
/// arrastra** a la segunda, y cada prórroga trae el suyo.
enum TimeoutSlot {
  /// Períodos 1-2. Dos por equipo.
  firstHalf,

  /// Períodos 3-4. Tres por equipo.
  secondHalf,

  /// Prórrogas. Uno por prórroga jugada.
  overtime;

  static TimeoutSlot forPeriod(int period) {
    if (period <= 2) return firstHalf;
    if (period <= GameClockRules.lastPeriod) return secondHalf;
    return overtime;
  }
}

/// Las reglas de tiempos muertos.
///
/// Vivían repartidas entre `addTimeout`, `_processTimeoutWithRules` y
/// `_updateTimeoutList` —tres métodos con un `if` de período cada uno— y no
/// tenían ni un test, pese a que lo que escriben acaba impreso en el acta.
abstract final class TimeoutEngine {
  static const int firstHalfLimit = 2;
  static const int secondHalfLimit = 3;

  /// Tope absoluto de tiempos muertos de prórroga, por muchas que se jueguen.
  static const int overtimeHardLimit = 3;

  /// Concede un tiempo muerto al equipo, si le queda alguno en su cupo.
  ///
  /// Devuelve `null` si el cupo está agotado: el equipo lo pidió pero no
  /// puede tenerlo, así que el estado no cambia y el llamador no debe
  /// registrarlo ni meterlo en el historial de deshacer.
  static MatchState? grant(MatchState state, String teamId) {
    final period = state.currentPeriod;
    final slot = TimeoutSlot.forPeriod(period);
    final isTeamA = teamId == TeamSide.home;

    final current = List<String>.from(_listFor(state, slot, isTeamA: isTeamA));
    final mark = minuteMark(state.timeLeft);

    switch (slot) {
      case TimeoutSlot.firstHalf:
        if (current.length >= firstHalfLimit) return null;
        current.add(mark);

      case TimeoutSlot.secondHalf:
        // En el "clutch time" el equipo que no haya gastado ninguno pierde
        // uno: no se pueden guardar los tres para los dos últimos minutos.
        if (_isClutchTime(state) && current.isEmpty) {
          current.add(GameClockRules.burnMark);
        }
        if (current.length >= secondHalfLimit) return null;
        current.add(mark);

      case TimeoutSlot.overtime:
        // Cada prórroga concede uno: en la segunda prórroga se pueden tener
        // dos acumulados, en la tercera tres.
        final allowed = period - GameClockRules.lastPeriod;
        if (current.length >= allowed || current.length >= overtimeHardLimit) {
          return null;
        }
        current.add(mark);
    }

    final withList = _withList(state, slot, isTeamA: isTeamA, list: current);
    return withList.copyWith(
      scoreLog: [
        ...withList.scoreLog,
        timeoutEvent(withList, teamId, EventType.timeoutFor(teamId)),
      ],
    );
  }

  /// El minuto que se anota en el acta junto al tiempo muerto.
  ///
  /// No es un redondeo normal, y es deliberado:
  ///   - `10:00` se anota como 10, pero `9:59` ya es 9;
  ///   - cualquier resto por debajo del minuto cuenta como 1, para que un
  ///     tiempo muerto pedido a falta de 20 segundos no figure como «minuto 0»;
  ///   - solo el reloj exactamente a cero anota 0.
  static String minuteMark(Duration timeLeft) {
    final seconds = timeLeft.inSeconds;
    if (seconds == 0) return '0';

    var minutes = seconds ~/ 60;
    if (seconds % 60 > 0 && minutes == 10) minutes = 9;
    if (minutes == 0) minutes = 1;
    return minutes.toString();
  }

  static bool _isClutchTime(MatchState state) =>
      state.currentPeriod == GameClockRules.lastPeriod &&
      state.timeLeft <= GameClockRules.autoBurnAt;

  static List<String> _listFor(
    MatchState s,
    TimeoutSlot slot, {
    required bool isTeamA,
  }) {
    return switch (slot) {
      TimeoutSlot.firstHalf => isTeamA ? s.teamATimeouts1 : s.teamBTimeouts1,
      TimeoutSlot.secondHalf => isTeamA ? s.teamATimeouts2 : s.teamBTimeouts2,
      TimeoutSlot.overtime => isTeamA ? s.teamAOTTimeouts : s.teamBOTTimeouts,
    };
  }

  /// El apunte que deja un tiempo fuera en el registro del partido.
  ///
  /// **No estaba, y esa era la causa de dos rarezas.** El menu de deshacer se
  /// habilita mirando `scoreLog`, asi que con solo tiempos fuera salia gris; y
  /// `TimeoutUndo.undoLast` los busca ahi, asi que no encontraba ninguno por
  /// ningun camino —ni en vivo ni al reconstruir—.
  ///
  /// Lo construye el dominio para que la forma sea la MISMA en los dos
  /// caminos. Que el mismo hecho tenga dos representaciones segun quien lo
  /// escriba es de donde han salido casi todos los fallos de este acta.
  static ScoreEvent timeoutEvent(MatchState state, String side, String type) {
    return ScoreEvent(
      period: state.currentPeriod,
      teamId: side,
      playerId: 'TIMEOUT_$side',
      playerNumber: '',
      points: 0,
      scoreAfter: side == TeamSide.home ? state.scoreA : state.scoreB,
      type: type,
    );
  }

  static MatchState _withList(
    MatchState s,
    TimeoutSlot slot, {
    required bool isTeamA,
    required List<String> list,
  }) {
    return switch ((slot, isTeamA)) {
      (TimeoutSlot.firstHalf, true) => s.copyWith(teamATimeouts1: list),
      (TimeoutSlot.firstHalf, false) => s.copyWith(teamBTimeouts1: list),
      (TimeoutSlot.secondHalf, true) => s.copyWith(teamATimeouts2: list),
      (TimeoutSlot.secondHalf, false) => s.copyWith(teamBTimeouts2: list),
      (TimeoutSlot.overtime, true) => s.copyWith(teamAOTTimeouts: list),
      (TimeoutSlot.overtime, false) => s.copyWith(teamBOTTimeouts: list),
    };
  }
}
