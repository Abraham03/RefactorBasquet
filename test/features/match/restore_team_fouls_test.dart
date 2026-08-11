// Regresión de campo: al cambiar el resultado de un partido, el acta
// regenerada salía SIN las faltas del entrenador ni las de banca, y sin el
// tiempo fuera que los equipos pierden automáticamente.
//
// Las dos causas son de restauración, no de dibujo:
//
//   1. La falta de banquillo se guarda como 'C_A' y en vivo es 'C'. El acta
//      filtra por la forma en vivo, así que con la larga no dibujaba nada.
//   2. La quema automática de tiempos fuera no deja evento en `gameEvents`
//      —solo toca el estado en memoria—, así que al reabrir se perdía.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
import 'package:myapp/features/match/domain/engines/game_clock.dart';
import 'package:myapp/features/match/domain/entities/match_restore_snapshot.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';

void main() {
  late AppDatabase db;
  late MatchGameController controller;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    controller = MatchGameController(db.matchesDao);

    await db
        .into(db.matches)
        .insert(
          MatchesCompanion.insert(
            id: const Value('M1'),
            teamAName: 'Lobos',
            teamBName: 'Pumas',
            currentPeriod: const Value(4),
            clockTime: const Value('01:30'),
          ),
        );
  });

  tearDown(() async {
    await pumpEventQueue();
    controller.dispose();
    await db.close();
  });

  Future<void> logEvent(
    String type, {
    String? playerId,
    int period = 4,
    String clockTime = '05:00',
  }) {
    return db
        .into(db.gameEvents)
        .insert(
          GameEventsCompanion.insert(
            matchId: 'M1',
            type: type,
            period: period,
            clockTime: clockTime,
            playerId: Value(playerId),
          ),
        );
  }

  Future<void> restore() => controller.restoreFromDatabase(
    const MatchRestoreSnapshot(
      matchId: 'M1',
      fixtureId: 'F1',
      rosterA: [],
      rosterB: [],
      startersA: {},
      startersB: {},
      tournamentId: 1,
      venueId: 7,
      teamAId: 3,
      teamBId: 4,
      mainReferee: 'Juan',
      auxReferee: 'Ana',
      scorekeeper: 'Luis',
    ),
    markFinished: true,
  );

  group('faltas de banquillo restauradas', () {
    test('la técnica al entrenador vuelve en su forma en vivo', () async {
      await logEvent(EventType.teamFoul(EventType.coach, TeamSide.home));
      await restore();

      final coachFouls = controller.state.scoreLog
          .where((e) => e.type == EventType.coach)
          .toList();

      expect(
        coachFouls,
        hasLength(1),
        reason: 'el acta filtra por "C"; con "C_A" no dibujaba la falta',
      );
      expect(coachFouls.single.teamId, TeamSide.home);
    });

    test('la falta de banca conserva el equipo correcto', () async {
      await logEvent(EventType.teamFoul(EventType.bench, TeamSide.away));
      await restore();

      final benchFouls = controller.state.scoreLog
          .where((e) => e.type == EventType.bench)
          .toList();

      expect(benchFouls, hasLength(1));
      expect(benchFouls.single.teamId, TeamSide.away);
    });

    test('las de un equipo no se cuelan en las del otro', () async {
      await logEvent(EventType.teamFoul(EventType.coach, TeamSide.home));
      await logEvent(EventType.teamFoul(EventType.coach, TeamSide.away));
      await logEvent(EventType.teamFoul(EventType.bench, TeamSide.home));
      await restore();

      final log = controller.state.scoreLog;
      expect(
        log
            .where(
              (e) => e.type == EventType.coach && e.teamId == TeamSide.home,
            )
            .length,
        1,
      );
      expect(
        log
            .where(
              (e) => e.type == EventType.coach && e.teamId == TeamSide.away,
            )
            .length,
        1,
      );
      expect(
        log
            .where(
              (e) => e.type == EventType.bench && e.teamId == TeamSide.home,
            )
            .length,
        1,
      );
    });

    test('no se contabilizan como falta personal de nadie', () async {
      await logEvent(EventType.teamFoul(EventType.coach, TeamSide.home));
      await restore();

      final withFouls = controller.state.playerStats.values.where(
        (p) => p.fouls > 0,
      );
      expect(withFouls, isEmpty);
    });
  });

  group('quema automática de tiempos fuera', () {
    test('se reconstruye al reabrir un partido que llegó al clutch', () async {
      // Período 4 a 1:30: ya se pasó el umbral de 2:00.
      await restore();

      expect(
        controller.state.teamATimeouts2,
        contains('X'),
        reason: 'no deja evento en gameEvents, hay que recalcularla',
      );
      expect(controller.state.teamBTimeouts2, contains('X'));
    });

    test('un partido CERRADO la aplica aunque el reloj no llegara', () async {
      // El caso que se escapó en la primera corrección: `setTime` no
      // persiste y `setPeriod` reinicia el reloj a 10:00, así que un acta
      // cerrada tras ajustar el tiempo a mano guarda "10:00" en el último
      // período. Mirando el reloj no se quemaba nada; mirando que el partido
      // llegó al último período, sí.
      await (db.update(db.matches)..where((t) => t.id.equals('M1'))).write(
        const MatchesCompanion(
          currentPeriod: Value(4),
          clockTime: Value('10:00'),
        ),
      );
      await restore();

      expect(controller.state.teamATimeouts2, contains('X'));
      expect(controller.state.teamBTimeouts2, contains('X'));
    });

    test('no se inventa si el partido no llegó al umbral', () async {
      await (db.update(db.matches)..where((t) => t.id.equals('M1'))).write(
        const MatchesCompanion(
          currentPeriod: Value(2),
          clockTime: Value('05:00'),
        ),
      );
      await restore();

      expect(controller.state.teamATimeouts2, isEmpty);
      expect(controller.state.teamBTimeouts2, isEmpty);
    });

    test('la quema persistida vuelve sola, en su sitio', () async {
      // El evento se guarda con su reloj (2:00), asi que al reproducirse en
      // orden cronologico cae DELANTE del tiempo fuera pedido a 1:58, sin
      // ninguna logica que lo coloque. Es la razon de persistirla.
      await logEvent(
        EventType.autoTimeoutFor(TeamSide.home),
        period: 4,
        clockTime: '2:00',
      );
      await logEvent(
        EventType.timeoutFor(TeamSide.home),
        period: 4,
        clockTime: '1:58',
      );

      await restore();

      expect(controller.state.teamATimeouts2, ['X', '1']);
    });

    test('la quema persistida no se duplica con el respaldo', () async {
      // El calculo de respaldo sigue ahi para las actas viejas, que no tienen
      // el evento. No debe anadir una segunda X cuando si lo hay.
      await logEvent(
        EventType.autoTimeoutFor(TeamSide.away),
        period: 4,
        clockTime: '2:00',
      );

      await restore();

      expect(controller.state.teamBTimeouts2, ['X']);
    });

    test('un acta vieja sin el evento sigue mostrando la marca', () async {
      // Compatibilidad: los partidos ya jugados no tienen `TIMEOUT_AUTO_`.
      // Si solo se reprodujera, sus actas perderian la X al reabrirlas.
      await restore();

      expect(controller.state.teamATimeouts2, ['X']);
      expect(controller.state.teamBTimeouts2, ['X']);
    });

    test('el pedido en CLUTCH no borra la quema, la lleva detras', () async {
      // Caso real de campo (partido COBRAS vs CLIPPERS, 11/08/2026):
      //   TIMEOUT_B P1 @ 9:09 · TIMEOUT_B P2 @ 3:56 · TIMEOUT_A P4 @ 1:54
      //
      // En vivo el acta salio con A2 = ['X', '1']: la quema salto a los 2:00
      // con la lista vacia y el local pidio el suyo despues, a 1:54. Al
      // reabrir salia ['1'] y se perdia la X, porque la quema solo se aplicaba
      // cuando la lista estaba VACIA.
      await logEvent(
        EventType.timeoutFor(TeamSide.away),
        period: 1,
        clockTime: '9:09',
      );
      await logEvent(
        EventType.timeoutFor(TeamSide.away),
        period: 2,
        clockTime: '3:56',
      );
      await logEvent(
        EventType.timeoutFor(TeamSide.home),
        period: 4,
        clockTime: '1:54',
      );

      await restore();

      expect(
        controller.state.teamATimeouts2,
        ['X', '1'],
        reason: 'la quema ocurre a los 2:00, ANTES del pedido de 1:54',
      );
      expect(controller.state.teamBTimeouts1, ['9', '3']);
      expect(
        controller.state.teamBTimeouts2,
        ['X'],
        reason:
            'el visitante gasto los dos de la primera mitad, no los de la segunda',
      );
    });

    test('quien gasto en el TERCER periodo no pierde ninguno', () async {
      // La otra cara: ['1'] puede ser el minuto 1 del cuarto (despues de la
      // quema, toca X) o el minuto 1 del tercero (antes, no toca). La lista
      // sola no lo distingue.
      await logEvent(
        EventType.timeoutFor(TeamSide.home),
        period: 3,
        clockTime: '1:00',
      );

      await restore();

      expect(controller.state.teamATimeouts2, ['1']);
      expect(controller.state.teamBTimeouts2, [GameClockRules.burnMark]);
    });

    test('respeta el tiempo fuera que el equipo sí pidió', () async {
      await logEvent(EventType.timeoutFor(TeamSide.home));
      await restore();

      // El local gastó uno de verdad, así que no se le quema ninguno; el
      // visitante, que no pidió, sí lo pierde.
      expect(controller.state.teamATimeouts2, isNot(contains('X')));
      expect(controller.state.teamATimeouts2, hasLength(1));
      expect(controller.state.teamBTimeouts2, contains('X'));
    });
  });
}
