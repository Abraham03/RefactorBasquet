import 'package:myapp/core/network/api_actions.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_download.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';

/// Torneos y catálogos: lo que se descarga para poder trabajar sin conexión.
class CatalogApi {
  CatalogApi(this._client);

  final ApiClient _client;

  Future<Result<List<Map<String, dynamic>>>> fetchCloudTournaments() {
    return _client.get(
      ApiActions.getTournamentsList,
      decode: (data) => List<Map<String, dynamic>>.from(data! as List),
    );
  }

  Future<Result<String>> createTournament(String name, String category) {
    return _client.postEnvelope(
      ApiActions.createTournament,
      body: {'name': name, 'category': category},
      decode: (envelope) {
        // Igual que en equipos y jugadores: `newId` llega dentro de `data` o
        // en la raíz del sobre según el endpoint. Se contemplan ambos.
        final data = envelope['data'];
        if (data is Map && data['newId'] != null) {
          return data['newId'].toString();
        }
        return envelope['newId']!.toString();
      },
    );
  }

  Future<Result<void>> saveTournamentRules({
    required String tournamentId,
    required int vueltas,
    required int ptsVictoria,
    required int ptsDerrota,
    required int ptsEmpate,
    required int ptsForfeitWin,
    required int ptsForfeitLoss,
  }) {
    return _client.postActionInBody(
      ApiActions.saveTournamentRules,
      body: {
        'tournament_id': tournamentId,
        // El orden de estas claves forma parte del golden: `points_draw` va
        // antes que `points_loss` aunque el parámetro Dart sea al revés.
        'config': {
          'matchups_per_pair': vueltas,
          'points_win': ptsVictoria,
          'points_draw': ptsEmpate,
          'points_loss': ptsDerrota,
          'points_forfeit_win': ptsForfeitWin,
          'points_forfeit_loss': ptsForfeitLoss,
        },
      },
      decode: (_) {},
    );
  }

  /// Datos de un torneo concreto: sedes, equipos, jugadores y relaciones.
  Future<Result<CatalogData>> fetchTournamentData(String tournamentId) {
    return _client.get(
      ApiActions.getTournamentData,
      query: {'tournament_id': tournamentId},
      decode: (raw) {
        final data = raw! as Map;
        return CatalogData(
          tournaments: [],
          venues: (data['venues'] as List)
              .map((e) => CatalogVenue.fromJson(e))
              .toList(),
          teams: (data['teams'] as List)
              .map((e) => CatalogTeam.fromJson(e))
              .toList(),
          players: (data['players'] as List)
              .map((e) => CatalogPlayer.fromJson(e))
              .toList(),
          relationships: (data['tournament_teams'] as List)
              .map((e) => TournamentTeamRelation.fromJson(e))
              .toList(),
          officials: [],
        );
      },
    );
  }

  /// Volcado completo para la sincronización de bajada.
  Future<Result<CatalogData>> fetchCatalogs(String tournamentId) {
    return _client.get(
      ApiActions.getSyncData,
      query: {'tournament_id': tournamentId},
      decode: (raw) {
        final data = raw! as Map;
        return CatalogData(
          tournaments: (data['tournaments'] as List)
              .map((e) => CatalogTournament.fromJson(e))
              .toList(),
          venues: (data['venues'] as List)
              .map((e) => CatalogVenue.fromJson(e))
              .toList(),
          teams: (data['teams'] as List)
              .map((e) => CatalogTeam.fromJson(e))
              .toList(),
          players: (data['players'] as List)
              .map((e) => CatalogPlayer.fromJson(e))
              .toList(),
          relationships: (data['tournament_teams'] as List)
              .map((e) => TournamentTeamRelation.fromJson(e))
              .toList(),
          fixtures: ((data['fixtures'] ?? []) as List)
              .map((e) => CatalogFixture.fromJson(e as Map<String, dynamic>))
              .toList(),
          officials: data['officials'] != null
              ? (data['officials'] as List)
                    .map((e) => CatalogOfficial.fromJson(e))
                    .toList()
              : [],
          finishedRosters: ((data['finished_rosters'] ?? []) as List)
              .map((e) => CatalogRoster.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
    );
  }
}
