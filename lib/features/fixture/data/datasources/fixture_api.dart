import 'package:myapp/core/network/api_actions.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/core/utils/json_parsing.dart';

/// Calendario: generación, edición manual y consulta del fixture.
class FixtureApi {
  FixtureApi(this._client);

  final ApiClient _client;

  /// Genera el rol completo del torneo.
  ///
  /// El backend responde con un `message` explicativo cuando lo rechaza por
  /// regla de negocio ("ya hay partidos jugados"). Ese mensaje llega ahora en
  /// `ApiBusinessException.message`, sin necesidad del `ApiResult` a medida.
  Future<Result<void>> generateFixture({required String tournamentId}) {
    return _client.postActionInBody(
      ApiActions.generateFixture,
      body: {'tournament_id': tournamentId},
      decode: (_) {},
    );
  }

  Future<Result<void>> deleteFixture({required String tournamentId}) {
    // El backend espera la clave 'id', no 'tournament_id', para esta acción.
    return _client.post(
      ApiActions.deleteFixture,
      body: {'id': tournamentId},
      decode: (_) {},
    );
  }

  Future<Result<Map<String, dynamic>>> fetchFixture(String tournamentId) {
    return _client.get(
      ApiActions.getFixture,
      query: {'tournament_id': tournamentId},
      decode: (data) => (data as Map).cast<String, dynamic>(),
    );
  }

  Future<Result<void>> updateFixtureTeams({
    required int fixtureId,
    required int newTeamAId,
    required int newTeamBId,
  }) {
    return _client.post(
      ApiActions.updateFixtureTeams,
      body: {
        'fixture_id': fixtureId,
        'new_team_a_id': newTeamAId,
        'new_team_b_id': newTeamBId,
      },
      decode: (_) {},
    );
  }

  Future<Result<void>> syncManualFixtures({
    required String tournamentId,
    required List<Map<String, dynamic>> fixtures,
  }) {
    return _client.post(
      ApiActions.syncManualFixtures,
      body: {'tournament_id': tournamentId, 'fixtures': fixtures},
      decode: (_) {},
    );
  }

  /// Devuelve el id real que asignó MySQL al partido creado a mano.
  Future<Result<int>> addManualFixture({
    required String tournamentId,
    required int roundOrder,
    required int teamAId,
    required int teamBId,
  }) {
    return _client.post(
      ApiActions.addManualFixture,
      body: {
        'tournament_id': tournamentId,
        'round_order': roundOrder,
        'team_a_id': teamAId,
        'team_b_id': teamBId,
      },
      decode: (data) => parseId((data! as Map)['fixture_id']),
    );
  }

  Future<Result<void>> deleteSingleFixture(int fixtureId) {
    return _client.post(
      ApiActions.deleteSingleFixture,
      body: {'fixture_id': fixtureId},
      decode: (_) {},
    );
  }

  Future<Result<List<Map<String, dynamic>>>> fetchTeamsSchedulingStatus(
    String tournamentId,
    int roundId,
  ) {
    return _client.get(
      ApiActions.getTeamSchedulingStatus,
      query: {'tournament_id': tournamentId, 'round_id': '$roundId'},
      decode: (data) => List<Map<String, dynamic>>.from(data! as List),
    );
  }
}
