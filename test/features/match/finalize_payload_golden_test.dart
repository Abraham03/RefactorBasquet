// GOLDEN DEL PAYLOAD DE CIERRE EN VIVO.
//
// Hay DOS caminos que suben un acta al mismo endpoint `sync_match`:
//   - `SyncRepository.uploadPendingData()`, para partidos ya cerrados que
//     esperaban conexión. Cubierto desde la Fase 6.
//   - `MatchGameController.finalizeAndSync()`, el cierre en vivo al terminar
//     el partido. **Este no lo estaba**, pese a ser el que corre con el
//     árbitro delante esperando el acta.
//
// Y las dos cabeceras NO son iguales, a propósito: ver el último grupo.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';

/// Captura el campo `data` del multipart de subida.
class _Capture {
  Map<String, dynamic>? payload;

  late final MockClient client = MockClient((request) async {
    if (request.url.queryParameters['action'] == 'sync_match') {
      final json = _dataField(request.body);
      if (json != null) payload = jsonDecode(json) as Map<String, dynamic>;
    }
    return http.Response('{"status":"success","data":{}}', 200);
  });

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
  late MatchGameController controller;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    capture = _Capture();
    controller = MatchGameController(db.matchesDao);

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
    await db
        .into(db.matches)
        .insert(
          MatchesCompanion.insert(
            id: const Value('M1'),
            teamAName: 'Lobos',
            teamBName: 'Pumas',
            fixtureId: const Value('F9'),
          ),
        );
    await db
        .into(db.matchRosters)
        .insert(
          MatchRostersCompanion.insert(
            matchId: 'M1',
            playerId: '9',
            teamSide: 'A',
            jerseyNumber: 12,
            isStarter: const Value(true),
          ),
        );
    await db
        .into(db.gameEvents)
        .insert(
          GameEventsCompanion.insert(
            matchId: 'M1',
            type: 'POINT_2',
            period: 1,
            clockTime: '09:30',
            playerId: const Value('9'),
          ),
        );
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<Map<String, dynamic>> finalize() async {
    controller
      ..initializeNewMatch(
        matchId: 'M1',
        fixtureId: 'F9',
        rosterA: const [],
        rosterB: const [],
        startersA: const {},
        startersB: const {},
        tournamentId: 7,
        venueId: 5,
        teamAId: 3,
        teamBId: 4,
        mainReferee: 'Juan',
        auxReferee: 'Ana',
        scorekeeper: 'Luis',
      )
      // El orden importa: `setPeriod` reinicia el reloj al arrancar un
      // período nuevo (10 min, o 5 en prórroga), así que el ajuste de tiempo
      // va después.
      ..setPeriod(3)
      ..setTime(const Duration(minutes: 4, seconds: 5))
      ..setObservaciones('Sin novedad');

    final api = MatchApi(ApiClient(client: capture.client));
    await controller.finalizeAndSync(api, null, null, 'Lobos', 'Pumas');

    expect(capture.payload, isNotNull, reason: 'no se capturó la subida');
    return capture.payload!;
  }

  test('la cabecera del acta lleva lo que el backend espera', () async {
    final payload = await finalize();

    expect(payload['match_id'], 'M1');
    expect(payload['fixture_id'], 'F9');
    expect(payload['tournament_id'], 7);
    expect(payload['venue_id'], 5);
    expect(payload['team_a_id'], 3);
    expect(payload['team_b_id'], 4);
    expect(payload['team_a_name'], 'Lobos');
    expect(payload['team_b_name'], 'Pumas');
    expect(payload['main_referee'], 'Juan');
    expect(payload['aux_referee'], 'Ana');
    expect(payload['scorekeeper'], 'Luis');
    expect(payload['observaciones'], 'Sin novedad');
  });

  test('el reloj y el período son los REALES, no marcadores de fin', () async {
    // Es la diferencia clave con la subida diferida: aquí el partido acaba de
    // cerrarse y se manda dónde estaba el reloj de verdad.
    final payload = await finalize();

    expect(payload['current_period'], 3);
    expect(payload['time_left'], '4:05');
  });

  test('la fecha va en el formato que parsea el backend', () async {
    final payload = await finalize();

    // YYYY-MM-DD HH:MM:SS
    expect(
      payload['match_date'],
      matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')),
    );
  });

  test(
    'los eventos salen de gameEvents, no solo del scoreLog en memoria',
    () async {
      // gameEvents incluye posesión, tiempos muertos y cambios; el scoreLog en
      // memoria solo trae anotación y faltas.
      final payload = await finalize();
      final events = (payload['events'] as List).cast<Map<String, dynamic>>();

      expect(events, hasLength(1));
      expect(events.single['type'], 'POINT_2');
      expect(events.single['player_id'], 9);
      expect(events.single['clock_time'], '09:30');
    },
  );

  test('el roster viaja con el titular marcado', () async {
    final payload = await finalize();
    final rosters = (payload['rosters'] as List).cast<Map<String, dynamic>>();

    expect(rosters, hasLength(1));
    expect(rosters.single['player_id'], 9);
    expect(rosters.single['is_starter'], 1);
  });

  test('los dos caminos de subida difieren a propósito', () async {
    // La subida diferida manda `current_period: 4`, `time_left: "00:00"` y una
    // clave `status`, porque son marcadores de "partido ya terminado" para un
    // acta que se cerró hace días. El cierre en vivo manda el estado real y no
    // manda `status`: el backend lo infiere.
    //
    // Queda escrito para que nadie "unifique" las dos cabeceras creyendo que
    // son la misma.
    final payload = await finalize();

    expect(payload.containsKey('status'), isFalse);
    expect(payload['time_left'], isNot('00:00'));
  });
}
