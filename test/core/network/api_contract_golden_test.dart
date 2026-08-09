// GOLDEN DEL CONTRATO CON EL BACKEND — invariante I2 del
// "Plan Estructura Limpia.md".
//
// Congela la petición HTTP exacta (método, URL, headers, body) que produce
// hoy cada método de `ApiService`. Las fases 3, 4 y 6 reescriben la capa de
// red, los modelos y el mapper de payload: este test es la única garantía de
// que el backend PHP no note el cambio.
//
//   ⚠️ Si un golden falla, la FASE está mal, no el fixture.
//      Nunca se regenera un fixture para "arreglar" un test en rojo.
//
// Regenerar (solo al agregar un método nuevo, nunca al refactorizar):
//   UPDATE_GOLDENS=true flutter test test/core/network/api_contract_golden_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/core/network/api_service.dart';

import '../../support/request_recorder.dart';

/// Directorio de los goldens, relativo a la raíz del proyecto.
const String _fixtureDir = 'test/fixtures/requests';

final bool _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == 'true';

/// Ejecuta [action] con un cliente que registra la petición y devuelve la
/// captura normalizada. Los errores de parseo se ignoran a propósito: lo que
/// se congela es lo que SALE, no lo que el método hace con la respuesta.
Future<CapturedRequest> _capture(
  Future<void> Function(ApiService api) action,
) async {
  final recorder = RecordingClient();
  await http.runWithClient(() async {
    try {
      await action(ApiService());
    } catch (_) {
      // Irrelevante: la petición ya quedó registrada antes del parseo.
    }
  }, () => recorder);
  return recorder.last;
}

/// Compara la captura contra `test/fixtures/requests/<name>.json`.
Future<void> _expectGolden(String name, CapturedRequest captured) async {
  final file = File('$_fixtureDir/$name.json');
  const encoder = JsonEncoder.withIndent('  ');
  final actual = '${encoder.convert(captured.toJson())}\n';

  if (_updateGoldens) {
    await file.parent.create(recursive: true);
    await file.writeAsString(actual);
    return;
  }

  if (!file.existsSync()) {
    fail(
      'Falta el golden ${file.path}.\n'
      'Si agregaste un método nuevo, regenera con:\n'
      '  UPDATE_GOLDENS=true flutter test ${Platform.script.pathSegments.last}',
    );
  }

  // En Windows git puede convertir LF -> CRLF al hacer checkout. El golden se
  // genera siempre con LF, así que se normaliza al comparar: si no, el test
  // fallaría en un clon limpio sin que nada del contrato haya cambiado.
  final expected = (await file.readAsString()).replaceAll('\r\n', '\n');

  expect(
    actual,
    equals(expected),
    reason:
        'La petición de "$name" cambió respecto al golden.\n'
        'Esto rompe el invariante I2 (contrato del backend intacto).\n'
        'Corrige el código: NO regeneres el fixture.',
  );
}

/// Payload de partido fijo y determinista (sin DateTime.now(), sin aleatorios).
Map<String, dynamic> get _matchPayload => {
  'match_id': 'M1',
  'tournament_id': 'T1',
  'team_a_id': 1,
  'team_b_id': 2,
  'score_a': 55,
  'score_b': 48,
  'status': 'FINISHED',
  'events': [
    {'type': 'POINT_2', 'player_id': '9', 'team_side': 'A', 'period': 1},
    {'type': 'P', 'player_id': '11', 'team_side': 'B', 'period': 2},
  ],
  'rosters': [
    {'player_id': '9', 'team_side': 'A', 'played': 1, 'attended': 1},
  ],
};

final Uint8List _pdfBytes = Uint8List.fromList(List<int>.filled(16, 42));

void main() {
  group('Golden del contrato con el backend (I2)', () {
    test('saveTournamentRules', () async {
      await _expectGolden(
        'save_tournament_rules',
        await _capture(
          (api) => api.saveTournamentRules(
            tournamentId: 'T1',
            vueltas: 2,
            ptsVictoria: 2,
            ptsDerrota: 1,
            ptsEmpate: 0,
            ptsForfeitWin: 2,
            ptsForfeitLoss: 0,
          ),
        ),
      );
    });

    test('createVenue', () async {
      await _expectGolden(
        'create_venue',
        await _capture(
          (api) => api.createVenue('Gimnasio Municipal', 'Av. Reforma 742'),
        ),
      );
    });

    test('updateVenue', () async {
      await _expectGolden(
        'update_venue',
        await _capture(
          (api) => api.updateVenue(
            id: '5',
            name: 'Gimnasio Municipal',
            address: 'Av. Reforma 742',
          ),
        ),
      );
    });

    test('deleteVenue', () async {
      await _expectGolden(
        'delete_venue',
        await _capture((api) => api.deleteVenue(5)),
      );
    });

    test('fetchCloudTournaments', () async {
      await _expectGolden(
        'get_tournaments_list',
        await _capture((api) => api.fetchCloudTournaments()),
      );
    });

    test('createTournament', () async {
      await _expectGolden(
        'create_tournament',
        await _capture((api) => api.createTournament('Liga 2026', 'VARONIL')),
      );
    });

    test('generateFixture', () async {
      await _expectGolden(
        'generate_fixture',
        await _capture((api) => api.generateFixture(tournamentId: 'T1')),
      );
    });

    test('deleteFixture', () async {
      await _expectGolden(
        'delete_fixture',
        await _capture((api) => api.deleteFixture(tournamentId: 'T1')),
      );
    });

    test('updateFixtureTeams', () async {
      await _expectGolden(
        'update_fixture_teams',
        await _capture(
          (api) => api.updateFixtureTeams(
            fixtureId: 10,
            newTeamAId: 1,
            newTeamBId: 2,
          ),
        ),
      );
    });

    test('syncManualFixtures', () async {
      await _expectGolden(
        'sync_manual_fixtures',
        await _capture(
          (api) => api.syncManualFixtures(
            tournamentId: 'T1',
            fixtures: [
              {'round_order': 1, 'team_a_id': 1, 'team_b_id': 2},
            ],
          ),
        ),
      );
    });

    test('addManualFixture', () async {
      await _expectGolden(
        'add_manual_fixture',
        await _capture(
          (api) => api.addManualFixture(
            tournamentId: 'T1',
            roundOrder: 1,
            teamAId: 1,
            teamBId: 2,
          ),
        ),
      );
    });

    test('deleteSingleFixture', () async {
      await _expectGolden(
        'delete_single_fixture',
        await _capture((api) => api.deleteSingleFixture(10)),
      );
    });

    test('fetchFixture', () async {
      await _expectGolden(
        'get_fixture',
        await _capture((api) => api.fetchFixture('T1')),
      );
    });

    test('fetchTournamentData', () async {
      await _expectGolden(
        'get_tournament_data',
        await _capture((api) => api.fetchTournamentData('T1')),
      );
    });

    test('fetchCatalogs', () async {
      await _expectGolden(
        'get_sync_data',
        await _capture((api) => api.fetchCatalogs('T1')),
      );
    });

    test('fetchTeamsSchedulingStatus', () async {
      await _expectGolden(
        'get_team_scheduling_status',
        await _capture((api) => api.fetchTeamsSchedulingStatus('T1', 2)),
      );
    });

    // `createTeam` tiene una rama: solo adjunta `tournament_id` cuando el
    // valor no es nulo/vacío/"true"/"false". Se congelan ambos caminos.
    test('createTeam (con tournamentId)', () async {
      await _expectGolden(
        'create_team_con_torneo',
        await _capture(
          (api) =>
              api.createTeam('Lobos', 'LOB', 'Coach Ruiz', tournamentId: 'T1'),
        ),
      );
    });

    test('createTeam (sin tournamentId)', () async {
      await _expectGolden(
        'create_team_sin_torneo',
        await _capture((api) => api.createTeam('Lobos', 'LOB', 'Coach Ruiz')),
      );
    });

    test('updateTeam', () async {
      await _expectGolden(
        'update_team',
        await _capture(
          (api) => api.updateTeam(
            id: '3',
            name: 'Lobos',
            shortName: 'LOB',
            coachName: 'Coach Ruiz',
          ),
        ),
      );
    });

    test('addPlayer', () async {
      await _expectGolden(
        'add_player',
        await _capture((api) => api.addPlayer(3, 'Pedro Gómez', 12)),
      );
    });

    test('updatePlayer', () async {
      await _expectGolden(
        'update_player',
        await _capture((api) => api.updatePlayer('9', 3, 'Pedro Gómez', 12)),
      );
    });

    test('createOfficial', () async {
      await _expectGolden(
        'create_official',
        await _capture(
          (api) => api.createOfficial(
            'Juan Pérez',
            'ARBITRO_PRINCIPAL',
            'iVBORw0KGgo=',
          ),
        ),
      );
    });

    test('updateOfficial', () async {
      await _expectGolden(
        'update_official',
        await _capture(
          (api) => api.updateOfficial(
            id: '7',
            name: 'Juan Pérez',
            role: 'ARBITRO_AUXILIAR',
            signature: 'iVBORw0KGgo=',
          ),
        ),
      );
    });

    test('deleteOfficial', () async {
      await _expectGolden(
        'delete_official',
        await _capture((api) => api.deleteOfficial(7)),
      );
    });

    test('syncMatchData', () async {
      await _expectGolden(
        'sync_match',
        await _capture((api) => api.syncMatchData(_matchPayload)),
      );
    });

    test('syncMatchDataMultipart (con PDF)', () async {
      await _expectGolden(
        'sync_match_multipart_con_pdf',
        await _capture(
          (api) => api.syncMatchDataMultipart(
            matchData: _matchPayload,
            pdfBytes: _pdfBytes,
          ),
        ),
      );
    });

    test('syncMatchDataMultipart (sin PDF)', () async {
      await _expectGolden(
        'sync_match_multipart_sin_pdf',
        await _capture(
          (api) => api.syncMatchDataMultipart(
            matchData: _matchPayload,
            pdfBytes: null,
          ),
        ),
      );
    });

    test('updateMatchAttendance', () async {
      await _expectGolden(
        'update_match_attendance',
        await _capture(
          (api) => api.updateMatchAttendance(
            matchId: 'M1',
            attendance: [
              {'player_id': '9', 'attended': 1},
              {'player_id': '11', 'attended': 0},
            ],
          ),
        ),
      );
    });

    test('updateMatchOutcome (con PDF)', () async {
      await _expectGolden(
        'update_match_outcome_con_pdf',
        await _capture(
          (api) => api.updateMatchOutcome(
            matchId: 'M1',
            forfeitStatus: 'NONE',
            observaciones: 'Sin novedad.',
            signatureBase64: 'iVBORw0KGgo=',
            scoreA: 55,
            scoreB: 48,
            tournamentId: 'T1',
            pdfBytes: _pdfBytes,
          ),
        ),
      );
    });

    test('updateMatchOutcome (sin PDF)', () async {
      await _expectGolden(
        'update_match_outcome_sin_pdf',
        await _capture(
          (api) => api.updateMatchOutcome(
            matchId: 'M1',
            forfeitStatus: 'TEAM_B',
            observaciones: 'Inasistencia del equipo B.',
            scoreA: 20,
            scoreB: 0,
            tournamentId: 'T1',
          ),
        ),
      );
    });

    test('getRealScores', () async {
      await _expectGolden(
        'get_real_scores',
        await _capture((api) => api.getRealScores('M1')),
      );
    });

    test('getMatchDetails', () async {
      await _expectGolden(
        'get_match_details',
        await _capture((api) => api.getMatchDetails('M1')),
      );
    });

    test('getMatchEvents', () async {
      await _expectGolden(
        'get_match_events',
        await _capture((api) => api.getMatchEvents('M1')),
      );
    });

    test('getMatchRosters', () async {
      await _expectGolden(
        'get_match_rosters',
        await _capture((api) => api.getMatchRosters('M1')),
      );
    });
  });

  test('el golden cubre las 30 acciones del backend', () async {
    // Se escanea TODO lib/ en vez de un archivo concreto: así el test
    // sobrevive tanto al movimiento de archivos de la Fase 1 como a la
    // división de ApiService en 5 datasources de la Fase 3.
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    // Acciones en la query string (`?action=x`) y en el body (`"action": "x"`).
    final actions = <String>{
      ...RegExp(r'action=([a-z_]+)').allMatches(source).map((m) => m.group(1)!),
      ...RegExp(
        r'"action"\s*:\s*"([a-z_]+)"',
      ).allMatches(source).map((m) => m.group(1)!),
    };

    final covered = Directory(_fixtureDir)
        .listSync()
        .whereType<File>()
        .map((f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)
        .expand((json) sync* {
          final url = json['url'] as String;
          final fromQuery = RegExp(r'action=([a-z_]+)').firstMatch(url);
          if (fromQuery != null) yield fromQuery.group(1)!;
          final body = json['body'];
          if (body is Map && body['action'] is String) {
            yield body['action'] as String;
          }
        })
        .toSet();

    expect(
      actions.difference(covered),
      isEmpty,
      reason:
          'Hay acciones de ApiService sin golden. '
          'Agrega un test y regenera con UPDATE_GOLDENS=true.',
    );
    expect(actions, hasLength(30));
  });
}
