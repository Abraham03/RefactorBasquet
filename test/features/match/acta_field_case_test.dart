// Caso de campo completo: partido CLIPPERS vs COBRAS (1786482211257).
//
// Se reproduce la secuencia EXACTA de eventos que el servidor recibió, para
// comprobar que el acta reconstruida coincide con la que se generó al cerrar
// el partido. Es la comparación que el usuario hace a ojo entre los dos PDF.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
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
            teamAName: 'CLIPPERS',
            teamBName: 'COBRAS',
            // Tal cual lo mandó la app: cuarto período, 1:58.
            currentPeriod: const Value(4),
            clockTime: const Value('1:58'),
          ),
        );
  });

  tearDown(() async {
    await pumpEventQueue();
    controller.dispose();
    await db.close();
  });

  Future<void> log(String type, int period, String clock) => db
      .into(db.gameEvents)
      .insert(
        GameEventsCompanion.insert(
          matchId: 'M1',
          type: type,
          period: period,
          clockTime: clock,
        ),
      );

  Future<void> restore() => controller.restoreFromDatabase(
    const MatchRestoreSnapshot(
      matchId: 'M1',
      fixtureId: '1515',
      rosterA: [],
      rosterB: [],
      startersA: {},
      startersB: {},
      tournamentId: 89,
      venueId: 1,
      teamAId: 160,
      teamBId: 163,
      mainReferee: 'ADOLFO CHARREZ',
      auxReferee: 'CARLOS OLVERA',
      scorekeeper: 'OLGA LETICIA MENDOZA MARTINEZ',
    ),
    markFinished: true,
  );

  /// Los tiempos fuera del partido, sin el que el anotador revirtió.
  Future<void> seedTimeouts() async {
    await log(EventType.timeoutFor(TeamSide.away), 1, '8:33');
    await log(EventType.timeoutFor(TeamSide.away), 2, '1:49');
    await log(EventType.timeoutFor(TeamSide.home), 4, '1:58');
  }

  test('el acta reconstruida coincide con la del cierre', () async {
    await seedTimeouts();
    await log(EventType.teamFoul(EventType.coach, TeamSide.home), 1, '8:26');
    await log(EventType.teamFoul(EventType.bench, TeamSide.home), 1, '8:28');
    await log(EventType.teamFoul(EventType.coach, TeamSide.away), 1, '8:30');

    await restore();

    // Lo que imprimió el acta original, casilla por casilla.
    expect(
      controller.state.teamATimeouts1,
      isEmpty,
      reason: 'el de 9:33 se revirtió; no debe existir',
    );
    expect(
      controller.state.teamATimeouts2,
      ['X', '1'],
      reason: 'la quema a los 2:00 precede al pedido de 1:58',
    );
    expect(controller.state.teamBTimeouts1, ['8', '1']);
    expect(
      controller.state.teamBTimeouts2,
      ['X'],
      reason: 'el visitante no pidió ninguno en la segunda mitad',
    );

    // Y las faltas de banquillo de los dos entrenadores.
    final coachFouls = controller.state.scoreLog.where(
      (e) => e.type == EventType.coach,
    );
    expect(
      coachFouls.map((e) => e.teamId),
      containsAll([TeamSide.home, TeamSide.away]),
    );
  });

  test(
    'un tiempo fuera NO revertido sí sale, y no desplaza la quema',
    () async {
      // El mismo partido si el anotador no hubiera deshecho el de 9:33: ese es
      // de la PRIMERA mitad, así que no afecta a la quema de la segunda.
      await seedTimeouts();
      await log(EventType.timeoutFor(TeamSide.home), 1, '9:33');

      await restore();

      expect(controller.state.teamATimeouts1, ['9']);
      expect(controller.state.teamATimeouts2, ['X', '1']);
    },
  );
}
