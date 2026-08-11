import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
import 'package:myapp/features/match/domain/engines/game_clock.dart';

/// La pila de deshacer del partido.
///
/// Era un `final List<MatchState> _history = []` suelto dentro del controller,
/// fuera del estado y sin forma de inspeccionarlo: deshacer es una función que
/// el anotador usa en medio de un partido en vivo y no tenía ni un test.
///
/// El límite existe porque cada entrada es un `MatchState` completo, con sus
/// mapas de estadísticas y su log de eventos: un partido largo acumularía
/// cientos y la memoria del dispositivo importa.
/// Un punto al que se puede volver.
class MatchSnapshot {
  const MatchSnapshot(this.state, this.loggedEvents);

  final MatchState state;

  /// Cuántos eventos llevaba escritos la sesión en ese momento.
  ///
  /// Deshacer tiene que **borrar de la base** los eventos registrados
  /// después, no solo revertir el estado en memoria. Sin esto, el acta en
  /// vivo salía correcta —se dibuja del estado— pero al reconstruir el
  /// partido los eventos deshechos volvían a aparecer, y además viajaban a
  /// la nube en el `sync_match`.
  final int loggedEvents;
}

class MatchHistory {
  MatchHistory({this.limit = 50});

  /// Cuántos pasos atrás se conservan.
  final int limit;

  final List<MatchSnapshot> _stack = [];

  bool get canUndo => _stack.isNotEmpty;
  int get length => _stack.length;

  /// Guarda un punto al que poder volver.
  void push(MatchState state, {int loggedEvents = 0}) {
    // Se descarta el más antiguo, no el más reciente: deshacer debe alcanzar
    // siempre los últimos [limit] pasos.
    if (_stack.length >= limit) _stack.removeAt(0);
    _stack.add(MatchSnapshot(state, loggedEvents));
  }

  /// Devuelve la instantánea anterior, o `null` si no hay nada que deshacer.
  MatchSnapshot? pop() => _stack.isEmpty ? null : _stack.removeLast();

  void clear() => _stack.clear();
}

/// Deshacer un tiempo fuera.
///
/// No entra en la pila general porque el anotador lo pide de forma explícita
/// («me equivoqué de equipo»), no como un paso atrás cualquiera: hay que
/// quitar ese tiempo fuera concreto y su evento del log.
abstract final class TimeoutUndo {
  /// Deshace el último tiempo fuera registrado.
  ///
  /// Devuelve `null` si no había ninguno.
  static MatchState? undoLast(MatchState state) {
    // La quema automática queda fuera: no es una acción del anotador, es la
    // regla de los dos últimos minutos. Deshacerla falsearía el acta, y
    // además volvería sola al reconstruir el partido, porque está persistida.
    final last = state.scoreLog
        .where(
          (e) =>
              EventType.isTimeout(e.type) && !EventType.isAutoTimeout(e.type),
        )
        .lastOrNull;
    if (last == null) return null;

    final lists = _TimeoutLists.from(state);
    lists.removeLastFor(teamId: last.teamId, period: last.period);

    return state.copyWith(
      teamATimeouts1: lists.a1,
      teamATimeouts2: lists.a2,
      teamAOTTimeouts: lists.aOt,
      teamBTimeouts1: lists.b1,
      teamBTimeouts2: lists.b2,
      teamBOTTimeouts: lists.bOt,
      // Se quita el evento concreto, no "el último": entre medias puede haber
      // habido canastas.
      scoreLog: state.scoreLog.where((e) => e != last).toList(),
    );
  }
}

/// Las seis listas de tiempos fuera, agrupadas para no repetir el `if` de
/// período en cada rama.
class _TimeoutLists {
  _TimeoutLists(this.a1, this.a2, this.aOt, this.b1, this.b2, this.bOt);

  factory _TimeoutLists.from(MatchState s) => _TimeoutLists(
    List<String>.from(s.teamATimeouts1),
    List<String>.from(s.teamATimeouts2),
    List<String>.from(s.teamAOTTimeouts),
    List<String>.from(s.teamBTimeouts1),
    List<String>.from(s.teamBTimeouts2),
    List<String>.from(s.teamBOTTimeouts),
  );

  final List<String> a1, a2, aOt, b1, b2, bOt;

  /// Los períodos 1-2 son la primera mitad, 3-4 la segunda, y de 5 en adelante
  /// prórroga: cada tramo tiene su cupo propio de tiempos fuera.
  void removeLastFor({required String teamId, required int period}) {
    final isTeamA = teamId == TeamSide.home;
    final list = switch (period) {
      <= 2 => isTeamA ? a1 : b1,
      <= 4 => isTeamA ? a2 : b2,
      _ => isTeamA ? aOt : bOt,
    };
    // Se quita la última marca que NO sea la de quema. Hoy la quema siempre
    // va delante, así que `removeLast` bastaría; se comprueba igualmente para
    // que un cambio de orden futuro no borre en silencio una marca que el
    // reglamento impone.
    final i = list.lastIndexWhere((m) => m != GameClockRules.burnMark);
    if (i >= 0) list.removeAt(i);
  }
}
