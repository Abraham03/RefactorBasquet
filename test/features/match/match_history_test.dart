// Deshacer: la pila general y el deshacer de tiempo muerto.
//
// El anotador usa deshacer en medio de un partido en vivo, y hasta ahora no
// tenía ni un test: `_history` era una lista suelta dentro del controller.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/match/domain/engines/match_history.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';

MatchState stateWith({
  int scoreA = 0,
  List<String> a1 = const [],
  List<String> a2 = const [],
  List<String> aOt = const [],
  List<String> b1 = const [],
  List<ScoreEvent> log = const [],
}) {
  return MatchState(
    matchId: 'M1',
    scoreA: scoreA,
    teamATimeouts1: a1,
    teamATimeouts2: a2,
    teamAOTTimeouts: aOt,
    teamBTimeouts1: b1,
    scoreLog: log,
  );
}

ScoreEvent timeout({required String teamId, required int period}) {
  return ScoreEvent(
    period: period,
    teamId: teamId,
    playerId: '',
    dbPlayerId: 0,
    playerNumber: '',
    points: 0,
    scoreAfter: 0,
    type: 'TIMEOUT_$teamId',
  );
}

void main() {
  group('MatchHistory', () {
    test('devuelve los estados en orden inverso', () {
      final history = MatchHistory()
        ..push(stateWith(scoreA: 1))
        ..push(stateWith(scoreA: 2));

      expect(history.pop()!.state.scoreA, 2);
      expect(history.pop()!.state.scoreA, 1);
      expect(history.pop(), isNull);
    });

    test('sin nada que deshacer devuelve null en vez de reventar', () {
      expect(MatchHistory().pop(), isNull);
      expect(MatchHistory().canUndo, isFalse);
    });

    test('al llegar al límite descarta el MÁS ANTIGUO', () {
      // Cada entrada es un MatchState completo, con sus mapas de estadísticas
      // y su log: sin límite, un partido largo se come la memoria. Pero hay
      // que poder deshacer siempre los últimos pasos, así que se tira el
      // viejo, no el nuevo.
      final history = MatchHistory(limit: 3);
      for (var i = 1; i <= 5; i++) {
        history.push(stateWith(scoreA: i));
      }

      expect(history.length, 3);
      expect(history.pop()!.state.scoreA, 5);
      expect(history.pop()!.state.scoreA, 4);
      expect(history.pop()!.state.scoreA, 3, reason: '1 y 2 se descartaron');
    });
  });

  group('Deshacer un tiempo muerto', () {
    test('lo quita de la lista del período correcto', () {
      // Períodos 1-2 primera mitad, 3-4 segunda, 5+ prórroga: cada tramo
      // tiene su cupo, así que hay que devolverlo al que corresponde.
      final state = stateWith(
        a1: const ['5'],
        a2: const ['3'],
        log: [timeout(teamId: 'A', period: 3)],
      );

      final undone = TimeoutUndo.undoLast(state)!;

      expect(undone.teamATimeouts2, isEmpty, reason: 'era de la 2ª mitad');
      expect(undone.teamATimeouts1, ['5'], reason: 'el de la 1ª no se toca');
    });

    test('un tiempo muerto de prórroga sale de la lista de prórroga', () {
      final state = stateWith(
        aOt: const ['1'],
        log: [timeout(teamId: 'A', period: 5)],
      );

      expect(TimeoutUndo.undoLast(state)!.teamAOTTimeouts, isEmpty);
    });

    test('se lo quita al equipo que lo pidió, no al otro', () {
      final state = stateWith(
        a1: const ['5'],
        b1: const ['7'],
        log: [timeout(teamId: 'B', period: 1)],
      );

      final undone = TimeoutUndo.undoLast(state)!;

      expect(undone.teamBTimeouts1, isEmpty);
      expect(undone.teamATimeouts1, [
        '5',
      ], reason: 'el rival no pierde el suyo');
    });

    test('elimina ESE evento del log, aunque haya canastas después', () {
      final theTimeout = timeout(teamId: 'A', period: 1);
      const basket = ScoreEvent(
        period: 1,
        teamId: 'A',
        playerId: '9',
        dbPlayerId: 9,
        playerNumber: '12',
        points: 2,
        scoreAfter: 2,
        type: 'POINT_2',
      );

      final state = stateWith(a1: const ['5'], log: [theTimeout, basket]);
      final undone = TimeoutUndo.undoLast(state)!;

      expect(undone.scoreLog, [basket], reason: 'la canasta se conserva');
    });

    test('sin tiempos muertos en el log devuelve null', () {
      // `null` evita que el controller guarde en el historial un paso que no
      // cambió nada: si no, deshacer haría falta dos veces.
      expect(TimeoutUndo.undoLast(stateWith()), isNull);
    });

    test('si la lista ya estaba vacía no revienta', () {
      // Puede pasar tras una descarga: el log viene de la nube pero las
      // listas en memoria arrancan vacías.
      final state = stateWith(log: [timeout(teamId: 'A', period: 1)]);

      final undone = TimeoutUndo.undoLast(state);

      expect(undone, isNotNull);
      expect(undone!.teamATimeouts1, isEmpty);
    });
  });
}
