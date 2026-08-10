// CatalogDownloadRepository: la sincronización de bajada.
//
// Esta lógica vivía dentro de `home_menu_screen._syncData()`, 272 líneas
// mezcladas con un diálogo de confirmación y tres SnackBars. Probarla exigía
// montar la pantalla entera, así que nunca se probó — pese a que **borra los
// datos locales del usuario**.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/errors/app_exception.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/features/catalog/data/datasources/catalog_api.dart';
import 'package:myapp/features/catalog/data/repositories/catalog_download_repository.dart';

/// Respuesta de `get_sync_data` con los campos que el repositorio consume.
String catalogPayload({
  String teamName = 'Lobos',
  List<Map<String, dynamic>> fixtures = const [],
  List<Map<String, dynamic>> finishedRosters = const [],
}) {
  return jsonEncode({
    'status': 'success',
    'data': {
      'tournaments': [
        {'id': '1', 'name': 'Liga 2026', 'category': 'VARONIL'},
      ],
      'venues': [
        {'id': '5', 'name': 'Gimnasio', 'address': 'Av. Reforma 742'},
      ],
      'teams': [
        {'id': '3', 'name': teamName, 'short_name': 'LOB'},
      ],
      'players': [
        {'id': '9', 'team_id': '3', 'name': 'Pedro', 'default_number': '12'},
      ],
      'tournament_teams': [
        {'tournament_id': '1', 'team_id': '3'},
      ],
      'officials': [
        {'id': '7', 'name': 'Juan', 'role': 'ARBITRO_PRINCIPAL'},
      ],
      'fixtures': fixtures,
      'finished_rosters': finishedRosters,
    },
  });
}

void main() {
  late AppDatabase db;

  CatalogDownloadRepository repoWith(String body, {int status = 200}) {
    final client = MockClient((_) async => http.Response(body, status));
    return CatalogDownloadRepository(db, CatalogApi(ApiClient(client: client)));
  }

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('downloadAll', () {
    test('inserta el catálogo completo y devuelve el resumen', () async {
      final result = await repoWith(
        catalogPayload(
          fixtures: [
            {
              'id': '100',
              'tournament_id': '1',
              'round_name': 'Jornada 1',
              'team_a_id': '3',
              'team_b_id': '4',
              'team_a': 'Lobos',
              'team_b': 'Pumas',
              'score_a': '55',
              'status': 'FINISHED',
            },
          ],
        ),
      ).downloadAll('1');

      expect(result, isA<Ok<dynamic>>());
      final summary = result.valueOrNull!;
      expect(summary.teams, 1);
      expect(summary.fixtures, 1);
      expect(summary.total, 6);

      expect(await db.select(db.teams).get(), hasLength(1));
      expect(await db.select(db.players).get(), hasLength(1));
      expect(await db.select(db.officials).get(), hasLength(1));

      final fixture = await db.select(db.fixtures).getSingle();
      expect(fixture.teamAName, 'Lobos');
      // El marcador llega como string desde PHP.
      expect(fixture.scoreA, 55);
      expect(fixture.scoreB, isNull, reason: 'no venía en el JSON');
    });

    test('el JSON de PHP se parsea con tipos, no a mano en la UI', () async {
      await repoWith(
        catalogPayload(
          finishedRosters: [
            {
              'match_id': 'M1',
              'player_id': '9',
              'team_side': 'A',
              'jersey_number': '12',
              'is_captain': '1',
              'attended': 0,
            },
          ],
        ),
      ).downloadAll('1');

      final roster = await db.select(db.matchRosters).getSingle();
      expect(roster.jerseyNumber, 12, reason: '"12" -> 12');
      expect(roster.isCaptain, isTrue, reason: '"1" -> true');
      expect(roster.attended, isFalse, reason: '0 -> false');
    });
  });

  group('qué se borra y qué se conserva', () {
    Future<void> seedMatch(String id, String status, {bool synced = true}) {
      return db
          .into(db.matches)
          .insert(
            MatchesCompanion.insert(
              id: Value(id),
              teamAName: 'A',
              teamBName: 'B',
              status: Value(status),
              isSynced: Value(synced),
            ),
          );
    }

    test('los partidos FINISHED sobreviven a la descarga', () async {
      // La nube no los vuelve a mandar: borrarlos perdería su historial
      // (rosters, asistencia, eventos) de forma irrecuperable.
      await seedMatch('finished-1', 'FINISHED');
      await seedMatch('a-medias', 'IN_PROGRESS');

      await repoWith(catalogPayload()).downloadAll('1');

      final remaining = await db.select(db.matches).get();
      expect(remaining.map((m) => m.id), ['finished-1']);
    });

    test('los partidos a medias se borran con sus eventos y rosters', () async {
      await seedMatch('a-medias', 'IN_PROGRESS');
      await db
          .into(db.gameEvents)
          .insert(
            GameEventsCompanion.insert(
              matchId: 'a-medias',
              type: 'POINT_2',
              period: 1,
              clockTime: '04:59',
            ),
          );

      await repoWith(catalogPayload()).downloadAll('1');

      expect(await db.select(db.matches).get(), isEmpty);
      expect(await db.select(db.gameEvents).get(), isEmpty);
    });
  });

  group('atomicidad', () {
    test('si la inserción falla a mitad, la base queda como estaba', () async {
      // Sembramos catálogo previo.
      await repoWith(catalogPayload()).downloadAll('1');
      expect(await db.select(db.teams).get(), hasLength(1));

      // Segunda descarga con un nombre de equipo que viola el CHECK de
      // longitud (max 100). El fallo ocurre DESPUÉS de haber borrado las
      // tablas: sin transacción, el usuario se quedaría sin catálogo.
      final result = await repoWith(
        catalogPayload(teamName: 'X' * 200),
      ).downloadAll('1');

      // Devuelve Err, no lanza: la pantalla solo contempla Ok/Err, así que una
      // excepción suelta subiría al framework sin que el usuario se entere.
      expect(result.errorOrNull, isA<StorageException>());

      expect(
        await db.select(db.teams).get(),
        hasLength(1),
        reason: 'la transacción revierte el borrado',
      );
      expect(await db.select(db.tournaments).get(), hasLength(1));
      expect(await db.select(db.officials).get(), hasLength(1));
    });
  });

  group('fallos de red', () {
    test('un error del backend devuelve Err y NO toca la base', () async {
      await repoWith(catalogPayload()).downloadAll('1');

      final result = await repoWith(
        '{"status":"error","message":"Torneo inexistente"}',
      ).downloadAll('99');

      expect(result.errorOrNull, isA<ApiBusinessException>());
      expect(result.errorOrNull!.message, 'Torneo inexistente');
      expect(
        await db.select(db.teams).get(),
        hasLength(1),
        reason: 'no se borra nada si la descarga ni siquiera llegó',
      );
    });

    test('un 500 devuelve Err con el código', () async {
      final result = await repoWith('boom', status: 500).downloadAll('1');
      expect(result.errorOrNull, isA<HttpStatusException>());
    });
  });

  group('pendingMatches', () {
    test('solo devuelve los no sincronizados', () async {
      await db
          .into(db.matches)
          .insert(
            MatchesCompanion.insert(
              id: const Value('pendiente'),
              teamAName: 'A',
              teamBName: 'B',
              isSynced: const Value(false),
            ),
          );
      await db
          .into(db.matches)
          .insert(
            MatchesCompanion.insert(
              id: const Value('subido'),
              teamAName: 'A',
              teamBName: 'B',
              isSynced: const Value(true),
            ),
          );

      final repo = repoWith(catalogPayload());
      final pending = await repo.pendingMatches();
      expect(pending.map((m) => m.id), ['pendiente']);
    });
  });
}
