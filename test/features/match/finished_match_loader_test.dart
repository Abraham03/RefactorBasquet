// FinishedMatchLoader: preparar un partido finalizado para corregirlo.
//
// Era un `onTap` de 263 líneas dentro de un `ListTile`. Su rama más delicada
// —el partido se jugó en OTRO dispositivo, así que no hay acta ni roster ni
// eventos locales y hay que bajarlo todo— no se podía probar sin montar la
// pantalla y tener red.
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
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/data/repositories/official_repository.dart';
import 'package:myapp/features/match/data/repositories/finished_match_loader.dart';

/// Backend que responde por acción, para poder fallar una sola.
class _Backend {
  Map<String, dynamic>? matchDetails;
  List<Map<String, dynamic>> rosters = const [];
  List<Map<String, dynamic>> events = const [];
  final Set<String> failing = {};
  final List<String> calls = [];

  MatchApi get api => MatchApi(ApiClient(client: _client));

  late final MockClient _client = MockClient((request) async {
    final action = request.url.queryParameters['action'] ?? '?';
    calls.add(action);
    if (failing.contains(action)) {
      return http.Response('{"status":"error","message":"sin red"}', 500);
    }
    final data = switch (action) {
      'get_match_details' => matchDetails,
      'get_match_rosters' => rosters,
      'get_match_events' => events,
      _ => null,
    };
    return http.Response(jsonEncode({'status': 'success', 'data': data}), 200);
  });
}

void main() {
  late AppDatabase db;
  late _Backend backend;
  late FinishedMatchLoader useCase;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = _Backend();
    useCase = FinishedMatchLoader(db, backend.api, OfficialRepository(db));

    await db
        .into(db.tournaments)
        .insert(
          TournamentsCompanion.insert(
            id: const Value('1'),
            name: 'Liga 2026',
            category: const Value('VARONIL'),
          ),
        );
    await db
        .into(db.teams)
        .insert(
          TeamsCompanion.insert(
            id: const Value('3'),
            name: 'Lobos',
            coachName: const Value('Coach A'),
          ),
        );
    await db
        .into(db.teams)
        .insert(
          TeamsCompanion.insert(
            id: const Value('4'),
            name: 'Pumas',
            coachName: const Value('Coach B'),
          ),
        );
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
  });

  tearDown(() async => db.close());

  Future<Fixture> seedFixture({String? matchId}) async {
    await db
        .into(db.fixtures)
        .insert(
          FixturesCompanion.insert(
            id: 'F1',
            tournamentId: '1',
            roundName: 'Jornada 1',
            teamAId: '3',
            teamBId: '4',
            teamAName: 'Lobos',
            teamBName: 'Pumas',
            venueName: const Value('Gimnasio'),
            matchId: Value(matchId),
            status: const Value('FINISHED'),
          ),
        );
    return (db.select(
      db.fixtures,
    )..where((f) => f.id.equals('F1'))).getSingle();
  }

  Future<void> seedLocalActa(String id) {
    return db
        .into(db.matches)
        .insert(
          MatchesCompanion.insert(
            id: Value(id),
            teamAName: 'Lobos',
            teamBName: 'Pumas',
            tournamentId: const Value('1'),
            teamAId: const Value(3),
            teamBId: const Value(4),
            mainReferee: const Value('Juan'),
            auxReferee: const Value('Ana'),
            scorekeeper: const Value('Luis'),
            status: const Value('FINISHED'),
            venueId: const Value('7'),
          ),
        );
  }

  group('partido jugado en ESTE dispositivo', () {
    test('usa el acta local y no llama al backend', () async {
      await seedLocalActa('M1');
      final fixture = await seedFixture(matchId: 'M1');

      final result = await useCase(fixture);

      expect(result.isOk, isTrue);
      expect(
        backend.calls,
        isNot(contains('get_match_details')),
        reason: 'el acta ya estaba en local',
      );

      final prepared = result.valueOrNull!;
      expect(prepared.matchId, 'M1');
      expect(prepared.snapshot.mainReferee, 'Juan');
      expect(prepared.snapshot.teamAId, 3);
      expect(prepared.pdfParams.coachA, 'Coach A');
      expect(prepared.pdfParams.tournamentName, 'Liga 2026');
      expect(prepared.pdfParams.venueName, 'Gimnasio');
    });

    test('el roster del equipo se arma desde los jugadores locales', () async {
      await seedLocalActa('M1');
      final fixture = await seedFixture(matchId: 'M1');

      final prepared = (await useCase(fixture)).valueOrNull!;

      expect(prepared.snapshot.rosterA.map((p) => p.name), ['Pedro']);
      expect(prepared.snapshot.rosterB, isEmpty);
    });
  });

  group('datos del acta al reabrir (regresión de campo)', () {
    // El usuario reportó que al cambiar un resultado, el acta regenerada salía
    // sin el nombre del entrenador y sin la sede. Estos tres campos alimentan
    // `OutcomeChanger`, que es quien vuelve a dibujar el PDF.

    test('el acta lleva los entrenadores de los dos equipos', () async {
      await seedLocalActa('M1');
      final fixture = await seedFixture(matchId: 'M1');

      final prepared = await useCase(fixture);
      final params = (prepared as Ok<PreparedMatch>).value.pdfParams;

      expect(params.coachA, 'Coach A');
      expect(params.coachB, 'Coach B');
    });

    test('la sede sale del PARTIDO, no del calendario', () async {
      // Se puede cambiar en el setup, así que la del acta es
      // `matches.venueId`. Antes se leía `fixture.venueName`, casi siempre
      // null, y la sede salía en blanco.
      await db
          .into(db.venues)
          .insert(
            VenuesCompanion.insert(
              id: const Value('7'),
              name: 'Gimnasio Municipal',
            ),
          );
      await seedLocalActa('M1');
      final fixture = await seedFixture(matchId: 'M1');

      final prepared = await useCase(fixture);
      final params = (prepared as Ok<PreparedMatch>).value.pdfParams;

      expect(params.venueName, 'Gimnasio Municipal');
    });

    test('sin sede en el partido, cae al calendario', () async {
      // No se siembra `venues`, así que la búsqueda por `matches.venueId`
      // no encuentra nada y queda el nombre que traía el calendario.
      await seedLocalActa('M1');
      final fixture = await seedFixture(matchId: 'M1');

      final prepared = await useCase(fixture);
      final params = (prepared as Ok<PreparedMatch>).value.pdfParams;

      expect(params.venueName, 'Gimnasio');
    });
  });

  group('partido jugado en OTRO dispositivo', () {
    test('baja acta, roster y eventos, y los deja en local', () async {
      backend.matchDetails = {
        'id': 'M9',
        'team_a_name': 'Lobos',
        'team_b_name': 'Pumas',
        'main_referee': 'Juan',
        'aux_referee': 'Ana',
        'scorekeeper': 'Luis',
        'tournament_id': '1',
        'team_a_id': '3',
        'team_b_id': '4',
      };
      backend.rosters = [
        {
          'player_id': '9',
          'team_side': 'A',
          'jersey_number': '12',
          'is_captain': '1',
          'is_starter': '1',
          'attended': '1',
        },
      ];
      backend.events = [
        {
          'event_type': 'POINT_2',
          'player_id': '9',
          'period': '1',
          'clock_time': '09:30',
        },
      ];

      final fixture = await seedFixture(matchId: 'M9');
      final result = await useCase(fixture);

      expect(result.isOk, isTrue);
      expect(
        backend.calls,
        containsAll([
          'get_match_details',
          'get_match_rosters',
          'get_match_events',
        ]),
      );

      // La fila `matches` es FK de rosters y eventos: sin ella nada de lo
      // anterior se puede insertar.
      expect(await db.select(db.matches).get(), hasLength(1));
      expect(await db.select(db.matchRosters).get(), hasLength(1));
      expect(await db.select(db.gameEvents).get(), hasLength(1));

      final prepared = result.valueOrNull!;
      expect(prepared.snapshot.startersA, {9});
      expect(prepared.pdfParams.captainAId, 9);
    });

    test('la fila `matches` se inserta UNA vez, no dos', () async {
      // El closure original la insertaba en dos ramas distintas con contenido
      // idéntico (duplicación (d) del plan).
      backend.matchDetails = {
        'id': 'M9',
        'team_a_name': 'Lobos',
        'team_b_name': 'Pumas',
        'tournament_id': '1',
        'team_a_id': '3',
        'team_b_id': '4',
      };
      final fixture = await seedFixture(matchId: 'M9');

      await useCase(fixture);

      final matches = await db.select(db.matches).get();
      expect(matches, hasLength(1));
      expect(matches.single.status, 'FINISHED');
    });

    test('si falla el acta, devuelve Err y no escribe nada', () async {
      backend.failing.add('get_match_details');
      final fixture = await seedFixture(matchId: 'M9');

      final result = await useCase(fixture);

      expect(result.errorOrNull, isA<AppException>());
      expect(
        await db.select(db.matches).get(),
        isEmpty,
        reason: 'sin acta no hay nada que preparar',
      );
    });

    test('si falla el roster, sigue adelante sin capitanes', () async {
      // Degradar es correcto: el acta sale sin la "X" del titular, pero el
      // usuario puede corregir el resultado igualmente.
      backend.matchDetails = {
        'id': 'M9',
        'team_a_name': 'Lobos',
        'team_b_name': 'Pumas',
        'tournament_id': '1',
        'team_a_id': '3',
        'team_b_id': '4',
      };
      backend.failing.add('get_match_rosters');
      final fixture = await seedFixture(matchId: 'M9');

      final result = await useCase(fixture);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.snapshot.startersA, isEmpty);
      expect(result.valueOrNull!.pdfParams.captainAId, isNull);
    });
  });

  group('hidratación de eventos', () {
    test('no baja eventos si ya hay locales', () async {
      await seedLocalActa('M1');
      await db
          .into(db.gameEvents)
          .insert(
            GameEventsCompanion.insert(
              matchId: 'M1',
              type: 'POINT_3',
              period: 1,
              clockTime: '05:00',
            ),
          );
      final fixture = await seedFixture(matchId: 'M1');

      await useCase(fixture);

      expect(backend.calls, isNot(contains('get_match_events')));
      expect(await db.select(db.gameEvents).get(), hasLength(1));
    });

    test('un evento antiguo sin event_type conserva la anotación', () async {
      await seedLocalActa('M1');
      backend.events = [
        {'points_scored': '3', 'period': '2', 'player_id': '9'},
      ];
      final fixture = await seedFixture(matchId: 'M1');

      await useCase(fixture);

      final event = await db.select(db.gameEvents).getSingle();
      expect(event.type, 'POINT_3');
      expect(event.clockTime, '00:00', reason: 'no venía en el JSON');
    });

    test('un player_id "0" se guarda como nulo', () async {
      // "0" significa "sin jugador" (falta de banca, tiempo fuera). Guardarlo
      // tal cual violaría la FK contra `players`.
      await seedLocalActa('M1');
      backend.events = [
        {'event_type': 'TIMEOUT_A', 'player_id': '0', 'period': '1'},
      ];
      final fixture = await seedFixture(matchId: 'M1');

      await useCase(fixture);

      final event = await db.select(db.gameEvents).getSingle();
      expect(event.playerId, isNull);
    });
  });
}
