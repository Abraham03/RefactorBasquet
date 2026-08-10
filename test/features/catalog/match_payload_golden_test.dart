// GOLDEN DEL PAYLOAD DE PARTIDO — paso 0 obligatorio de la Fase 6.
//
// El mapper evento→payload estaba duplicado byte a byte entre
// `sync_repository` y `match_game_controller`. Antes de unificarlo hay que
// congelar lo que produce HOY: es lo que recibe el backend PHP (invariante I2)
// y un cambio silencioso ahí rompe actas ya subidas.
//
// Se captura por el camino real —`uploadPendingData()` contra una BD sembrada
// y un `MockClient`— así que lo que se compara es literalmente el cuerpo de la
// petición, no una reconstrucción de laboratorio.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/features/catalog/data/datasources/catalog_api.dart';
import 'package:myapp/features/catalog/data/repositories/sync_repository.dart';
import 'package:myapp/features/fixture/data/datasources/fixture_api.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/data/datasources/official_venue_api.dart';
import 'package:myapp/features/teams/data/datasources/team_api.dart';
import 'package:myapp/features/teams/data/repositories/player_repository.dart';

/// Captura el campo `data` de la subida multipart del acta.
class _Capture {
  Map<String, dynamic>? matchPayload;

  late final MockClient client = MockClient((request) async {
    if (request.url.queryParameters['action'] == 'sync_match') {
      final json = _dataField(request.body);
      if (json != null) {
        matchPayload = jsonDecode(json) as Map<String, dynamic>;
      }
    }
    return http.Response('{"status":"success","data":{}}', 200);
  });

  /// El acta viaja en el campo `data` de un multipart y `MockClient` entrega
  /// el cuerpo ya serializado, asi que hay que sacarlo de ahi.
  ///
  /// Se parte por el boundary en vez de usar una expresion regular: el JSON
  /// del acta lleva llaves, comillas y saltos, y cualquier patron acaba siendo
  /// mas fragil que buscar la seccion.
  static String? _dataField(String body) {
    for (final part in body.split('--dart-http-boundary')) {
      if (!part.contains('name="data"')) continue;
      final start = part.indexOf('{');
      final end = part.lastIndexOf('}');
      if (start == -1 || end <= start) return null;
      return part.substring(start, end + 1);
    }
    return null;
  }
}

void main() {
  late AppDatabase db;
  late _Capture capture;
  late SyncRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    capture = _Capture();
    final api = ApiClient(client: capture.client);
    repo = SyncRepository(
      db,
      db.matchesDao,
      playerRepository: PlayerRepository(db, TeamApi(api), db.matchesDao),
      catalogApi: CatalogApi(api),
      officialVenueApi: OfficialVenueApi(api),
      teamApi: TeamApi(api),
      fixtureApi: FixtureApi(api),
      matchApi: MatchApi(api),
    );

    // --- Semilla: un partido finalizado con dos jugadores y tres jugadas ---
    await db
        .into(db.teams)
        .insert(TeamsCompanion.insert(id: const Value('3'), name: 'Lobos'));
    await db
        .into(db.teams)
        .insert(TeamsCompanion.insert(id: const Value('4'), name: 'Pumas'));
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
    await db
        .into(db.players)
        .insert(
          PlayersCompanion.insert(
            id: const Value('11'),
            teamId: 4,
            name: 'Ana',
            defaultNumber: const Value(7),
          ),
        );

    await db
        .into(db.matches)
        .insert(
          MatchesCompanion.insert(
            id: const Value('M1'),
            teamAName: 'Lobos',
            teamBName: 'Pumas',
            teamAId: const Value(3),
            teamBId: const Value(4),
            tournamentId: const Value('1'),
            status: const Value('FINISHED'),
            scoreA: const Value(5),
            scoreB: const Value(3),
            mainReferee: const Value('Juan'),
            auxReferee: const Value('Ana R'),
            scorekeeper: const Value('Luis'),
            isSynced: const Value(false),
          ),
        );

    for (final r in [
      (playerId: '9', side: 'A', number: 12, captain: true, starter: true),
      (playerId: '11', side: 'B', number: 7, captain: false, starter: true),
    ]) {
      await db
          .into(db.matchRosters)
          .insert(
            MatchRostersCompanion.insert(
              matchId: 'M1',
              playerId: r.playerId,
              teamSide: r.side,
              jerseyNumber: r.number,
              isCaptain: Value(r.captain),
              isStarter: Value(r.starter),
              attended: const Value(true),
            ),
          );
    }

    // POINT_2 y POINT_3 de A, falta de banca de B con sufijo de lado.
    final events = [
      (type: 'POINT_2', player: '9', period: 1, clock: '09:30'),
      (type: 'POINT_3', player: '9', period: 2, clock: '05:00'),
      (type: 'C_B', player: null, period: 2, clock: '04:00'),
    ];
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      await db
          .into(db.gameEvents)
          .insert(
            GameEventsCompanion.insert(
              matchId: 'M1',
              type: e.type,
              period: e.period,
              clockTime: e.clock,
              playerId: Value(e.player),
              createdAt: Value(DateTime(2026).add(Duration(seconds: i))),
            ),
          );
    }
  });

  tearDown(() async => db.close());

  test('el payload del acta no cambia', () async {
    await repo.uploadPendingData();

    final payload = capture.matchPayload;
    expect(payload, isNotNull, reason: 'no se capturó ninguna subida');

    // --- Eventos ---
    final events = (payload!['events'] as List).cast<Map<String, dynamic>>();
    expect(events, hasLength(3));

    expect(events[0], {
      'period': 1,
      'team_side': 'A',
      'player_name': 'Pedro',
      'player_number': 12,
      'points_scored': 2,
      'score_after': 2,
      // `type` conserva el sufijo original: el restore lo necesita íntegro.
      'type': 'POINT_2',
      'clock_time': '09:30',
      'player_id': 9,
    });

    expect(
      events[1]['score_after'],
      5,
      reason: 'el marcador es acumulado por equipo, no por evento',
    );

    // El sufijo `_B` fija el lado y se quita para calcular los puntos.
    expect(events[2]['team_side'], 'B');
    expect(events[2]['type'], 'C_B', reason: 'el tipo viaja SIN limpiar');
    expect(events[2]['points_scored'], 0);
    expect(
      events[2]['player_id'],
      isNull,
      reason: 'una falta de banca no tiene jugador',
    );

    // --- Rosters ---
    final rosters = (payload['rosters'] as List).cast<Map<String, dynamic>>();
    expect(rosters, hasLength(2));

    final pedro = rosters.firstWhere((r) => r['player_id'] == 9);
    expect(pedro, {
      'player_id': 9,
      'team_side': 'A',
      'is_starter': 1,
      'jersey_number': 12,
      'is_captain': 1,
      // `played` se deriva de haber aparecido en algún evento.
      'played': 1,
      'attended': 1,
    });

    final ana = rosters.firstWhere((r) => r['player_id'] == 11);
    expect(ana['played'], 0, reason: 'Ana no aparece en ningún evento');

    // --- Cabecera ---
    expect(payload['match_id'], 'M1');
    expect(payload['score_a'], 5);
    expect(payload['score_b'], 3);
  });

  test('un equipo en forfeit no jugó, aunque tenga titulares', () async {
    // El forfeit manda sobre los titulares elegidos en la UI: si no se
    // presentaron, `played` debe ser 0 para todo el equipo.
    await (db.update(db.matches)..where((m) => m.id.equals('M1'))).write(
      const MatchesCompanion(forfeitStatus: Value('TEAM_A')),
    );

    await repo.uploadPendingData();

    final rosters = (capture.matchPayload!['rosters'] as List)
        .cast<Map<String, dynamic>>();
    final pedro = rosters.firstWhere((r) => r['player_id'] == 9);
    expect(pedro['played'], 0, reason: 'el equipo A no se presentó');
  });
}
