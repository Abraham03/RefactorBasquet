// Regresión de campo: deshacer no borraba el evento de la base.
//
// El acta en vivo salía correcta —se dibuja del estado en memoria— pero el
// partido reconstruido resucitaba lo deshecho, y el `sync_match` se lo
// llevaba a la nube. En el caso reportado quedaron tres `TIMEOUT_A` que el
// anotador había revertido, y aparecieron en el acta al cambiar el resultado.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
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
          ),
        );
    await db
        .into(db.teams)
        .insert(TeamsCompanion.insert(id: const Value('3'), name: 'Lobos'));
    await db
        .into(db.players)
        .insert(
          PlayersCompanion.insert(
            id: const Value('9'),
            teamId: 3,
            name: 'Pedro',
            defaultNumber: const Value(12),
          ),
        );

    controller.initializeNewMatch(
      matchId: 'M1',
      fixtureId: 'F1',
      rosterA: const [],
      rosterB: const [],
      startersA: const {},
      startersB: const {},
      tournamentId: 1,
      venueId: 7,
      teamAId: 3,
      teamBId: 4,
      mainReferee: 'Juan',
      auxReferee: 'Ana',
      scorekeeper: 'Luis',
    );
  });

  tearDown(() async {
    await pumpEventQueue();
    controller.dispose();
    await db.close();
  });

  Future<List<String>> eventTypes() async {
    final rows = await db.select(db.gameEvents).get();
    return rows.map((e) => e.type).toList();
  }

  test('deshacer un tiempo muerto lo borra de la base', () async {
    controller.addTimeout(TeamSide.home);
    await pumpEventQueue();
    expect(await eventTypes(), [EventType.timeoutFor(TeamSide.home)]);

    controller.undo();
    await pumpEventQueue();

    expect(
      await eventTypes(),
      isEmpty,
      reason: 'quedaba en gameEvents y resucitaba al reconstruir el acta',
    );
  });

  test('deshacer tres veces los borra los tres', () async {
    // El caso reportado: se registraron varios tiempos muertos de prueba y se
    // revirtieron; los tres siguieron en la base y viajaron a la nube.
    controller
      ..addTimeout(TeamSide.home)
      ..addTimeout(TeamSide.away)
      ..addTimeout(TeamSide.home);
    await pumpEventQueue();
    expect(await eventTypes(), hasLength(3));

    controller
      ..undo()
      ..undo()
      ..undo();
    await pumpEventQueue();

    expect(await eventTypes(), isEmpty);
  });

  test('deshacer NO se lleva por delante lo anterior', () async {
    controller.addTimeout(TeamSide.home);
    await pumpEventQueue();
    controller.addTimeout(TeamSide.away);
    await pumpEventQueue();

    controller.undo();
    await pumpEventQueue();

    expect(await eventTypes(), [
      EventType.timeoutFor(TeamSide.home),
    ], reason: 'solo se deshace el último paso');
  });

  test('deshacer una falta de banquillo la borra con su lado', () async {
    // En la base se guarda 'C_A'; en memoria es 'C'. Si el borrado buscara la
    // forma en vivo no encontraría la fila.
    controller.addTeamFoul(TeamSide.home, EventType.coach);
    await pumpEventQueue();
    expect(await eventTypes(), [
      EventType.teamFoul(EventType.coach, TeamSide.home),
    ]);

    controller.undoLastFoul();
    await pumpEventQueue();

    expect(await eventTypes(), isEmpty);
  });

  test('un evento de OTRA sesión no se toca al deshacer', () async {
    // Un partido reanudado trae eventos de antes. El deshacer general solo
    // puede borrar los que ha escrito esta sesión.
    await db
        .into(db.gameEvents)
        .insert(
          GameEventsCompanion.insert(
            matchId: 'M1',
            type: EventType.timeoutFor(TeamSide.away),
            period: 1,
            clockTime: '08:00',
          ),
        );

    controller.addTimeout(TeamSide.home);
    await pumpEventQueue();
    controller.undo();
    await pumpEventQueue();

    expect(await eventTypes(), [EventType.timeoutFor(TeamSide.away)]);
  });
}
