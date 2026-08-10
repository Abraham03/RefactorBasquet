// PlayerRepository contra una BD real en memoria y un backend simulado.
//
// Este repositorio concentra la lógica offline-first más frágil del proyecto
// —ids temporales negativos y el rodeo por el dorsal #9999 para esquivar el
// deadlock de dorsal único del backend— y hasta ahora no tenía ni un test.
//
// Ahora es posible porque `TeamApi` recibe un `ApiClient` inyectable: se
// sustituye el transporte con `MockClient`, sin necesidad de abstraerlo tras
// una interfaz.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/features/teams/data/datasources/team_api.dart';
import 'package:myapp/features/teams/data/repositories/player_repository.dart';

/// Backend simulado que registra las acciones recibidas, en orden.
class _FakeBackend {
  final List<String> actions = [];
  final List<Map<String, dynamic>> bodies = [];
  bool failEverything = false;

  TeamApi get api => TeamApi(ApiClient(client: _client));

  late final MockClient _client = MockClient((request) async {
    if (failEverything) {
      return http.Response('{"status":"error","message":"sin red"}', 500);
    }
    actions.add(request.url.queryParameters['action'] ?? '?');
    bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response('{"status":"success","data":{"newId":"77"}}', 200);
  });
}

void main() {
  late AppDatabase db;
  late _FakeBackend backend;
  late PlayerRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = _FakeBackend();
    repo = PlayerRepository(db, backend.api, db.matchesDao);

    await db
        .into(db.teams)
        .insert(TeamsCompanion.insert(id: const Value('3'), name: 'Lobos'));
  });

  tearDown(() async => db.close());

  Future<void> seedPlayer({
    required String id,
    required int number,
    String name = 'Jugador',
    bool synced = true,
  }) {
    return db
        .into(db.players)
        .insert(
          PlayersCompanion.insert(
            id: Value(id),
            teamId: 3,
            name: name,
            defaultNumber: Value(number),
            isSynced: Value(synced),
          ),
        );
  }

  group('findPlayerByNumber', () {
    test('encuentra al que ya usa el dorsal', () async {
      await seedPlayer(id: '9', number: 12);
      final found = await repo.findPlayerByNumber(teamId: 3, number: 12);
      expect(found?.id, '9');
    });

    test('excluye al jugador que se está editando', () async {
      await seedPlayer(id: '9', number: 12);
      final found = await repo.findPlayerByNumber(
        teamId: 3,
        number: 12,
        excludePlayerId: '9',
      );
      expect(found, isNull);
    });
  });

  group('createPlayer', () {
    test(
      'con red: guarda el id REAL del backend y lo marca sincronizado',
      () async {
        final result = await repo.createPlayer(
          teamId: 3,
          name: 'Pedro',
          number: 12,
          isTeamLocal: false,
        );

        expect(result.synced, isTrue);
        expect(result.playerId, '77');
        expect(backend.actions, ['add_player']);

        final saved = await db.select(db.players).getSingle();
        expect(saved.id, '77');
        expect(saved.isSynced, isTrue);
      },
    );

    test('sin red: cae a offline con id NEGATIVO y sin sincronizar', () async {
      backend.failEverything = true;

      final result = await repo.createPlayer(
        teamId: 3,
        name: 'Pedro',
        number: 12,
        isTeamLocal: false,
      );

      expect(result.synced, isFalse);
      expect(
        int.parse(result.playerId),
        isNegative,
        reason: 'el id temporal debe ser negativo para no chocar con la nube',
      );

      final saved = await db.select(db.players).getSingle();
      expect(saved.isSynced, isFalse);
    });

    test('equipo local: ni siquiera intenta la nube', () async {
      // Un equipo que aún no existe en el backend haría fallar el insert
      // remoto por clave foránea.
      final result = await repo.createPlayer(
        teamId: 3,
        name: 'Pedro',
        number: 12,
        isTeamLocal: true,
      );

      expect(result.synced, isFalse);
      expect(backend.actions, isEmpty);
    });
  });

  group('updatePlayer', () {
    test('con id real y equipo en la nube: sincroniza', () async {
      await seedPlayer(id: '9', number: 12);

      final result = await repo.updatePlayer(
        playerId: '9',
        teamId: 3,
        name: 'Pedro Editado',
        number: 15,
        isTeamLocal: false,
      );

      expect(result.synced, isTrue);
      expect(backend.actions, ['update_player']);

      final saved = await db.select(db.players).getSingle();
      expect(saved.name, 'Pedro Editado');
      expect(saved.defaultNumber, 15);
    });

    test(
      'con id temporal negativo: guarda local sin llamar a la nube',
      () async {
        // Un id negativo aún no existe en el backend: llamarlo daría 404.
        await seedPlayer(id: '-123', number: 12, synced: false);

        final result = await repo.updatePlayer(
          playerId: '-123',
          teamId: 3,
          name: 'Pedro',
          number: 15,
          isTeamLocal: false,
        );

        expect(result.synced, isFalse);
        expect(backend.actions, isEmpty);
      },
    );

    test('el fallo de la nube no impide guardar en local', () async {
      await seedPlayer(id: '9', number: 12);
      backend.failEverything = true;

      final result = await repo.updatePlayer(
        playerId: '9',
        teamId: 3,
        name: 'Pedro Offline',
        number: 15,
        isTeamLocal: false,
      );

      expect(result.synced, isFalse, reason: 'queda pendiente de subir');
      final saved = await db.select(db.players).getSingle();
      expect(saved.name, 'Pedro Offline', reason: 'offline-first');
      expect(saved.isSynced, isFalse);
    });
  });

  group('reassignNumber — rodeo anti-deadlock', () {
    test(
      'libera primero el dorsal al #9999 y luego asigna el definitivo',
      () async {
        // El backend impone dorsal único por equipo. Intercambiar dos dorsales
        // de golpe se bloquea a sí mismo: hay que sacar uno de en medio antes.
        await seedPlayer(id: '9', number: 12, name: 'A');
        await seedPlayer(id: '11', number: 15, name: 'B');

        final duplicate = await repo.findPlayerByNumber(teamId: 3, number: 15);

        await repo.reassignNumber(
          duplicatePlayer: duplicate!,
          newNumber: 12,
          teamId: 3,
          isTeamLocal: false,
          freeUpFirstId: '9',
          freeUpFirstName: 'A',
        );

        expect(backend.actions, ['update_player', 'update_player']);
        expect(
          backend.bodies.first['number'],
          9999,
          reason: 'la primera llamada aparca al otro jugador en el #9999',
        );
        expect(backend.bodies.last['number'], 12);

        final moved = await (db.select(
          db.players,
        )..where((p) => p.id.equals('11'))).getSingle();
        expect(moved.defaultNumber, 12);
        expect(moved.isSynced, isTrue);
      },
    );

    test('equipo local: no toca la nube y queda sin sincronizar', () async {
      await seedPlayer(id: '11', number: 15);
      final duplicate = await repo.findPlayerByNumber(teamId: 3, number: 15);

      await repo.reassignNumber(
        duplicatePlayer: duplicate!,
        newNumber: 12,
        teamId: 3,
        isTeamLocal: true,
      );

      expect(backend.actions, isEmpty);
      final moved = await db.select(db.players).getSingle();
      expect(moved.defaultNumber, 12);
      expect(moved.isSynced, isFalse);
    });
  });

  group('uploadPendingPlayers', () {
    test(
      'reconcilia el id temporal en TODAS las tablas, no solo en players',
      () async {
        // Esta es la razon de fondo para unificar: la copia que vivia en
        // starters_selection_screen solo revinculaba `players` y
        // `gameEvents.playerId`. Dejaba `matchRosters` y, peor, los ids
        // incrustados en el TEXTO de los eventos SUB apuntando al id negativo.
        const tempId = '-123';
        await seedPlayer(
          id: tempId,
          number: 12,
          name: 'Offline',
          synced: false,
        );
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
            .into(db.matchRosters)
            .insert(
              MatchRostersCompanion.insert(
                matchId: 'M1',
                playerId: tempId,
                teamSide: 'A',
                jerseyNumber: 12,
              ),
            );
        await db
            .into(db.gameEvents)
            .insert(
              GameEventsCompanion.insert(
                matchId: 'M1',
                type: 'SUB_A_OUT_${tempId}_IN_9',
                period: 1,
                clockTime: '05:00',
              ),
            );

        final uploaded = await repo.uploadPendingPlayers();

        expect(uploaded, 1);
        expect(backend.actions, ['add_player']);

        final roster = await db.select(db.matchRosters).getSingle();
        expect(roster.playerId, '77', reason: 'matchRosters revinculado');

        final event = await db.select(db.gameEvents).getSingle();
        expect(
          event.type,
          'SUB_A_OUT_77_IN_9',
          reason: 'el id incrustado en el texto del SUB tambien se revincula',
        );

        final players = await db.select(db.players).get();
        expect(players.map((p) => p.id), contains('77'));
        expect(players.map((p) => p.id), isNot(contains(tempId)));
      },
    );

    test('aparca los dorsales en +1000 antes de reasignarlos', () async {
      await seedPlayer(id: '9', number: 12, synced: false);

      await repo.uploadPendingPlayers();

      expect(backend.actions, ['update_player', 'update_player']);
      expect(backend.bodies.first['number'], 12 + 1000);
      expect(backend.bodies.last['number'], 12);
    });

    test('un jugador que falla no bloquea a los demas', () async {
      await seedPlayer(id: '9', number: 12, synced: false);
      backend.failEverything = true;

      final uploaded = await repo.uploadPendingPlayers();

      expect(uploaded, 0);
      final saved = await db.select(db.players).getSingle();
      expect(saved.isSynced, isFalse, reason: 'queda pendiente de reintentar');
    });
  });
}
