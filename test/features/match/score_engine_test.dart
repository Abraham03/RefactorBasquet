// Las reglas de anotación y falta.
//
// Son el corazón de la app —lo que decide el marcador que acaba firmado en el
// acta— y vivían dentro de un método de 96 líneas del controller, mezcladas
// con la persistencia. Nunca tuvieron un test.
//
// Ahora son una función pura: se prueban sin base de datos, sin red y sin
// montar una pantalla.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/match/domain/engines/score_engine.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';

/// Partido con Pedro (#12) en el equipo A y Ana (#7) en el B.
MatchState baseState({
  int pedroFouls = 0,
  int currentPeriod = 1,
  Map<int, List<int>>? periodScores,
}) {
  return MatchState(
    matchId: 'M1',
    currentPeriod: currentPeriod,
    periodScores:
        periodScores ??
        const {
          1: [0, 0],
        },
    teamAOnCourt: const ['9'],
    teamBOnCourt: const ['11'],
    playerStats: {
      '9': PlayerStats(
        dbId: 9,
        playerName: 'Pedro',
        playerNumber: '12',
        fouls: pedroFouls,
      ),
      '11': const PlayerStats(dbId: 11, playerName: 'Ana', playerNumber: '7'),
    },
  );
}

MatchState applied(ScoreOutcome outcome) => (outcome as ScoreApplied).state;

void main() {
  group('Anotación', () {
    test('suma al marcador del equipo y al del jugador', () {
      final state = applied(
        ScoreEngine.applyPlayerAction(
          baseState(),
          teamId: 'A',
          playerId: '9',
          points: 3,
        ),
      );

      expect(state.scoreA, 3);
      expect(state.scoreB, 0);
      expect(state.playerStats['9']!.points, 3);
    });

    test('acumula en el marcador del período EN CURSO', () {
      final state = applied(
        ScoreEngine.applyPlayerAction(
          baseState(
            currentPeriod: 2,
            periodScores: {
              1: [10, 8],
              2: [0, 0],
            },
          ),
          teamId: 'B',
          playerId: '11',
          points: 2,
        ),
      );

      expect(state.periodScores[2], [0, 2]);
      expect(state.periodScores[1], [10, 8], reason: 'el 1º no se toca');
    });

    test('un período sin marcador previo arranca en 0-0', () {
      final state = applied(
        ScoreEngine.applyPlayerAction(
          baseState(currentPeriod: 4, periodScores: const {}),
          teamId: 'A',
          playerId: '9',
          points: 2,
        ),
      );

      expect(state.periodScores[4], [2, 0]);
    });

    test('NO muta el marcador por período del estado anterior', () {
      // El historial de deshacer guarda estados enteros. Si la lista interna
      // se compartiera, deshacer devolvería el marcador de período nuevo.
      final before = baseState();
      final snapshot = List<int>.from(before.periodScores[1]!);

      ScoreEngine.applyPlayerAction(
        before,
        teamId: 'A',
        playerId: '9',
        points: 2,
      );

      expect(before.periodScores[1], snapshot);
    });

    test('el evento registra el marcador DESPUÉS de la canasta', () {
      final outcome =
          ScoreEngine.applyPlayerAction(
                baseState(),
                teamId: 'A',
                playerId: '9',
                points: 2,
              )
              as ScoreApplied;

      expect(outcome.event!.scoreAfter, 2);
      expect(outcome.event!.type, 'POINT_2');
      expect(outcome.event!.playerNumber, '12');
      expect(outcome.event!.dbPlayerId, 9);
    });
  });

  group('Faltas', () {
    test('suma la falta y guarda su código', () {
      final state = applied(
        ScoreEngine.applyPlayerAction(
          baseState(),
          teamId: 'A',
          playerId: '9',
          fouls: 1,
          foulType: 'U',
        ),
      );

      expect(state.playerStats['9']!.fouls, 1);
      expect(state.playerStats['9']!.foulDetails, ['U']);
    });

    test('sin código explícito se registra como personal simple', () {
      final state = applied(
        ScoreEngine.applyPlayerAction(
          baseState(),
          teamId: 'A',
          playerId: '9',
          fouls: 1,
        ),
      );

      expect(state.playerStats['9']!.foulDetails, ['P']);
    });

    test('una falta no altera el marcador', () {
      final state = applied(
        ScoreEngine.applyPlayerAction(
          baseState(),
          teamId: 'A',
          playerId: '9',
          fouls: 1,
        ),
      );

      expect(state.scoreA, 0);
      expect(state.periodScores[1], [0, 0]);
    });
  });

  group('Reglas que RECHAZAN la acción', () {
    test('a la quinta falta el jugador queda descalificado', () {
      final outcome = ScoreEngine.applyPlayerAction(
        baseState(pedroFouls: ScoreEngine.foulLimit),
        teamId: 'A',
        playerId: '9',
        points: 2,
      );

      expect(outcome, isA<ScoreRejected>());
      expect((outcome as ScoreRejected).reason, ScoreRejection.disqualified);
    });

    test('con 4 faltas todavía puede jugar', () {
      final outcome = ScoreEngine.applyPlayerAction(
        baseState(pedroFouls: 4),
        teamId: 'A',
        playerId: '9',
        fouls: 1,
      );

      expect(outcome, isA<ScoreApplied>());
      expect(applied(outcome).playerStats['9']!.fouls, 5);
    });

    test('no se le puede anotar a un jugador del OTRO equipo', () {
      // Protege contra un toque en la mitad equivocada de la pantalla: sin
      // esto, el punto se sumaría al marcador contrario.
      final outcome = ScoreEngine.applyPlayerAction(
        baseState(),
        teamId: 'A',
        playerId: '11',
        points: 2,
      );

      expect((outcome as ScoreRejected).reason, ScoreRejection.wrongTeam);
    });

    test('un jugador que no está en el partido se rechaza', () {
      final outcome = ScoreEngine.applyPlayerAction(
        baseState(),
        teamId: 'A',
        playerId: 'fantasma',
        points: 2,
      );

      expect((outcome as ScoreRejected).reason, ScoreRejection.unknownPlayer);
    });

    test('un jugador en BANCA sí cuenta para su equipo', () {
      // Una falta técnica desde el banquillo es legítima.
      final state = baseState().copyWith(
        teamAOnCourt: const [],
        teamABench: const ['9'],
      );

      final outcome = ScoreEngine.applyPlayerAction(
        state,
        teamId: 'A',
        playerId: '9',
        fouls: 1,
      );

      expect(outcome, isA<ScoreApplied>());
    });
  });

  group('Acciones sin efecto', () {
    test('0 puntos y 0 faltas no genera evento', () {
      // El controller usa esto para decidir si registrar en la BD: sin el
      // dato tendría que adivinarlo.
      final outcome =
          ScoreEngine.applyPlayerAction(baseState(), teamId: 'A', playerId: '9')
              as ScoreApplied;

      expect(outcome.event, isNull);
      expect(outcome.state.scoreLog, isEmpty);
    });

    test('un jugador descalificado sí admite una corrección de 0', () {
      // El rechazo solo aplica a acciones reales; corregir datos debe poder
      // hacerse siempre.
      final outcome = ScoreEngine.applyPlayerAction(
        baseState(pedroFouls: 5),
        teamId: 'A',
        playerId: '9',
      );

      expect(outcome, isA<ScoreApplied>());
    });
  });
}
