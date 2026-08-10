import 'package:myapp/core/network/api_actions.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/core/utils/json_parsing.dart';

/// Equipos y jugadores.
class TeamApi {
  TeamApi(this._client);

  final ApiClient _client;

  Future<Result<int>> createTeam(
    String name,
    String shortName,
    String coach, {
    String? tournamentId,
  }) {
    final body = <String, Object?>{
      'name': name,
      'shortName': shortName,
      'coachName': coach,
    };

    // El torneo solo viaja si es un id de verdad. Los centinelas "true"/"false"
    // vienen de una llamada antigua que pasaba un bool por error; enviarlos
    // haría que el backend intentara asociar el equipo a un torneo inexistente.
    if (tournamentId != null &&
        tournamentId.isNotEmpty &&
        tournamentId != 'true' &&
        tournamentId != 'false') {
      body['tournament_id'] = tournamentId;
    }

    return _client.postEnvelope(
      ApiActions.createTeam,
      body: body,
      decode: _newId,
    );
  }

  Future<Result<void>> updateTeam({
    required String id,
    required String name,
    required String shortName,
    required String coachName,
  }) {
    return _client.post(
      ApiActions.updateTeam,
      body: {
        'id': id,
        'name': name,
        'shortName': shortName,
        'coachName': coachName,
      },
      decode: (_) {},
    );
  }

  Future<Result<int>> addPlayer(int teamId, String name, int number) {
    return _client.postEnvelope(
      ApiActions.addPlayer,
      body: {'teamId': teamId, 'name': name, 'number': number},
      decode: _newId,
    );
  }

  Future<Result<void>> updatePlayer(
    String id,
    int teamId,
    String name,
    int number,
  ) {
    return _client.post(
      ApiActions.updatePlayer,
      body: {'id': id, 'teamId': teamId, 'name': name, 'number': number},
      decode: (_) {},
    );
  }

  /// El backend devuelve `newId` unas veces dentro de `data` y otras en la raíz
  /// del sobre. Ambos caminos existen hoy en producción, así que se conservan:
  /// perder el segundo rompería altas que funcionan.
  static int _newId(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is Map && data['newId'] != null) return parseId(data['newId']);
    return parseId(envelope['newId']);
  }
}
