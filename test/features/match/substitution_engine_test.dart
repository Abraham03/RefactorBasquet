// Los cambios de jugador.
//
// Vivían en un método de 79 líneas con la rama del equipo A y la del B
// duplicadas casi palabra por palabra, y sin un solo test.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/match/domain/engines/substitution_engine.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';

/// A: #9 y #10 en cancha, #11 en banca. B: #20 en cancha, #21 en banca.
MatchState baseState() {
  return const MatchState(
    matchId: 'M1',
    currentPeriod: 2,
    teamAOnCourt: ['9', '10'],
    teamABench: ['11'],
    teamBOnCourt: ['20'],
    teamBBench: ['21'],
    playerStats: {
      '9': PlayerStats(
        dbId: 9,
        playerName: 'Pedro',
        playerNumber: '9',
        isOnCourt: true,
      ),
      '10': PlayerStats(
        dbId: 10,
        playerName: 'Luis',
        playerNumber: '10',
        isOnCourt: true,
      ),
      '11': PlayerStats(dbId: 11, playerName: 'Ana', playerNumber: '11'),
      '20': PlayerStats(
        dbId: 20,
        playerName: 'Rival',
        playerNumber: '20',
        isOnCourt: true,
      ),
      '21': PlayerStats(dbId: 21, playerName: 'Suplente', playerNumber: '21'),
    },
  );
}

MatchState? sub(MatchState s, String team, String out, String inId) =>
    SubstitutionEngine.substitute(
      s,
      teamId: team,
      playerOutId: out,
      playerInId: inId,
    );

void main() {
  group('Cambio válido', () {
    test('intercambia cancha y banca', () {
      final state = sub(baseState(), 'A', '9', '11')!;

      expect(state.teamAOnCourt, containsAll(['10', '11']));
      expect(state.teamAOnCourt, isNot(contains('9')));
      expect(state.teamABench, ['9']);
    });

    test('actualiza quién está en cancha en las estadísticas', () {
      final state = sub(baseState(), 'A', '9', '11')!;

      expect(state.playerStats['9']!.isOnCourt, isFalse);
      expect(state.playerStats['11']!.isOnCourt, isTrue);
    });

    test('entrar a cancha cuenta como haber jugado', () {
      // Aunque no anote ni cometa falta, en el acta debe figurar como
      // participante.
      final state = sub(baseState(), 'A', '9', '11')!;
      expect(state.playerStats['11']!.hasPlayed, isTrue);
    });

    test('no toca al equipo contrario', () {
      final state = sub(baseState(), 'A', '9', '11')!;

      expect(state.teamBOnCourt, ['20']);
      expect(state.teamBBench, ['21']);
    });

    test('funciona igual para el equipo B', () {
      // Las dos ramas estaban duplicadas: este test las mantiene alineadas.
      final state = sub(baseState(), 'B', '20', '21')!;

      expect(state.teamBOnCourt, ['21']);
      expect(state.teamBBench, ['20']);
      expect(state.teamAOnCourt, ['9', '10'], reason: 'A intacto');
    });
  });

  group('El evento del acta', () {
    test('registra quién sale y quién entra', () {
      // `playerId` guarda al que SALE y `playerNumber` al que ENTRA:
      // ScoreEvent no tiene huecos propios para un cambio y deshacer depende
      // de esta convención.
      final state = sub(baseState(), 'A', '9', '11')!;
      final event = state.scoreLog.last;

      expect(event.type, 'SUB');
      expect(event.playerId, '9', reason: 'el que sale');
      expect(event.playerNumber, '11', reason: 'el que entra');
      expect(event.period, 2);
      expect(event.points, 0);
    });
  });

  group('Cambios que se rechazan', () {
    test('cambiar a un jugador por sí mismo', () {
      // Dejaría un evento SUB sin significado en el acta y, al reproducirlo
      // en el restore, sacaría al jugador de cancha.
      expect(sub(baseState(), 'A', '9', '9'), isNull);
    });

    test('sacar a alguien que NO está en cancha', () {
      // Sin esta comprobación, el `remove` no hacía nada y el entrante se
      // añadía igual: seis jugadores en cancha.
      expect(sub(baseState(), 'A', '11', '11'), isNull);
      expect(sub(baseState(), 'A', 'fantasma', '11'), isNull);
    });

    test('meter a alguien que NO está en banca', () {
      // Un doble toque sobre el mismo botón duplicaría al jugador.
      expect(sub(baseState(), 'A', '9', '10'), isNull);
    });

    test('mezclar jugadores de equipos distintos', () {
      // #21 es del B: no está en la banca del A.
      expect(sub(baseState(), 'A', '9', '21'), isNull);
    });

    test('un cambio rechazado no deja rastro', () {
      final before = baseState();
      expect(sub(before, 'A', '9', '9'), isNull);
      expect(before.scoreLog, isEmpty, reason: 'no se registró nada');
    });
  });

  group('Reversibilidad', () {
    test('deshacer un cambio devuelve a cada uno a su sitio', () {
      // Es lo que hace `undoLastSub`: invertir los papeles.
      final after = sub(baseState(), 'A', '9', '11')!;
      final undone = sub(after, 'A', '11', '9')!;

      expect(undone.teamAOnCourt, containsAll(['9', '10']));
      expect(undone.teamABench, ['11']);
      expect(undone.playerStats['9']!.isOnCourt, isTrue);
      expect(undone.playerStats['11']!.isOnCourt, isFalse);
    });

    test('pero el que entró sigue constando como que jugó', () {
      // Correcto: pisó la cancha, aunque fuera un momento.
      final after = sub(baseState(), 'A', '9', '11')!;
      final undone = sub(after, 'A', '11', '9')!;

      expect(undone.playerStats['11']!.hasPlayed, isTrue);
    });
  });
}
