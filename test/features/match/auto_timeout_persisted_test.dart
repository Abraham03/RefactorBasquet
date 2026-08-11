// La quema de tiempos fuera deja constancia en la base.
//
// Antes solo vivía en memoria y había que recalcularla al reconstruir el
// partido —tres intentos costó acertar el cálculo—. Persistirla la convierte
// en un evento más: se escribe en local siempre y viaja a la nube en la
// siguiente sincronización, así que **funciona sin conexión sin nada
// especial**. El `sync_match` la recoge de `gameEvents` como a las demás.

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
    controller.setPeriod(4);
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

  test('se escribe un evento por cada equipo al que se le quema', () async {
    controller.burnUnusedTimeouts();
    await pumpEventQueue();

    expect(
      await eventTypes(),
      containsAll([
        EventType.autoTimeoutFor(TeamSide.home),
        EventType.autoTimeoutFor(TeamSide.away),
      ]),
    );
  });

  test('al equipo que ya gastó el suyo no se le escribe nada', () async {
    controller.addTimeout(TeamSide.home);
    await pumpEventQueue();

    controller.burnUnusedTimeouts();
    await pumpEventQueue();

    final types = await eventTypes();
    expect(types, contains(EventType.autoTimeoutFor(TeamSide.away)));
    expect(
      types,
      isNot(contains(EventType.autoTimeoutFor(TeamSide.home))),
      reason: 'el local gastó el suyo; no pierde ninguno',
    );
  });

  test('el evento queda en local aunque no haya red', () async {
    // No hay nada que distinga el caso offline: se escribe en `gameEvents`
    // como cualquier evento y sube cuando toque. Este test lo fija para que
    // a nadie se le ocurra condicionarlo a la conectividad.
    controller.burnUnusedTimeouts();
    await pumpEventQueue();

    final rows = await db.select(db.gameEvents).get();
    final burn = rows.firstWhere((e) => EventType.isAutoTimeout(e.type));

    expect(burn.isSynced, isFalse, reason: 'pendiente de subir, como el resto');
    expect(burn.period, 4);
    expect(burn.matchId, 'M1');
  });

  test('llamarlo dos veces no duplica la marca', () async {
    // Salta por reloj a los 2:00 y otra vez al cerrar el partido.
    controller.burnUnusedTimeouts();
    await pumpEventQueue();
    controller.burnUnusedTimeouts();
    await pumpEventQueue();

    expect(controller.state.teamATimeouts2, ['X']);
    expect(
      (await eventTypes())
          .where((t) => t == EventType.autoTimeoutFor(TeamSide.home))
          .length,
      1,
    );
  });
}
