// lib/core/services/api_service.dart
import 'dart:typed_data';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/features/catalog/data/datasources/catalog_api.dart';
import 'package:myapp/features/fixture/data/datasources/fixture_api.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/data/datasources/official_venue_api.dart';
import 'package:myapp/features/teams/data/datasources/team_api.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';
import 'package:myapp/core/network/result.dart';

/// **Fachada en extinción.**
///
/// Era una God class de 30 métodos con `http.post` top-level (no inyectable) y
/// tres convenciones de error incompatibles. La Fase 3 la vacía por dominios:
/// cada método pasa a delegar en su datasource, que devuelve `Result`.
///
/// Se conserva la firma pública EXACTA de cada método (`Future<bool>`, `throw`,
/// `ApiResult`) para no tocar las ~7 pantallas que la consumen: eso es la
/// Fase 3.3. Patrón **Strangler Fig**: el código nuevo crece por dentro
/// mientras la interfaz vieja sigue en pie.
class ApiService {
  ApiService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  late final OfficialVenueApi _officialVenue = OfficialVenueApi(_client);
  late final CatalogApi _catalog = CatalogApi(_client);
  late final FixtureApi _fixture = FixtureApi(_client);
  late final TeamApi _teams = TeamApi(_client);
  late final MatchApi _match = MatchApi(_client);

  /// Traduce un `Result` al viejo `Future<bool>`.
  ///
  /// Pierde la causa del fallo, igual que antes. Es deuda deliberada y
  /// temporal: desaparece en la Fase 3.3, cuando los llamadores consuman
  /// `Result` directamente.
  static bool _asBool(Result<void> result) => result.isOk;

  /// Traduce un `Result` al viejo `ApiResult`.
  static ApiResult _asApiResult(Result<void> result) =>
      ApiResult.from(result.map((_) => null));

  /// Traduce un `Result` al viejo `throw Exception('<contexto>: ...')`.
  static T _orThrow<T>(Result<T> result, String context) => switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw Exception('$context: ${error.message}'),
  };

  Future<bool> saveTournamentRules({
    required String tournamentId,
    required int vueltas,
    required int ptsVictoria,
    required int ptsDerrota,
    required int ptsEmpate,
    required int ptsForfeitWin,
    required int ptsForfeitLoss,
  }) async {
    return _asBool(
      await _catalog.saveTournamentRules(
        tournamentId: tournamentId,
        vueltas: vueltas,
        ptsVictoria: ptsVictoria,
        ptsDerrota: ptsDerrota,
        ptsEmpate: ptsEmpate,
        ptsForfeitWin: ptsForfeitWin,
        ptsForfeitLoss: ptsForfeitLoss,
      ),
    );
  }

  // ==========================================
  // --- FUNCIONES PARA SEDES (VENUES) ---
  // ==========================================
  Future<int> createVenue(String name, String address) async {
    return _orThrow(
      await _officialVenue.createVenue(name, address),
      'Error creando sede',
    );
  }

  Future<bool> updateVenue({
    required String id,
    required String name,
    required String address,
  }) async {
    return _asBool(
      await _officialVenue.updateVenue(id: id, name: name, address: address),
    );
  }

  // --- NUEVO: OBTENER LISTA DE TORNEOS DESDE LA NUBE ---
  Future<List<Map<String, dynamic>>> fetchCloudTournaments() async {
    return (await _catalog.fetchCloudTournaments()).valueOrNull ?? [];
  }

  Future<ApiResult> generateFixture({required String tournamentId}) async {
    return _asApiResult(
      await _fixture.generateFixture(tournamentId: tournamentId),
    );
  }

  Future<bool> updateFixtureTeams({
    required int fixtureId,
    required int newTeamAId,
    required int newTeamBId,
  }) async {
    return _asBool(
      await _fixture.updateFixtureTeams(
        fixtureId: fixtureId,
        newTeamAId: newTeamAId,
        newTeamBId: newTeamBId,
      ),
    );
  }

  Future<bool> syncManualFixtures({
    required String tournamentId,
    required List<Map<String, dynamic>> fixtures,
  }) async {
    return _asBool(
      await _fixture.syncManualFixtures(
        tournamentId: tournamentId,
        fixtures: fixtures,
      ),
    );
  }

  Future<ApiResult> deleteFixture({required String tournamentId}) async {
    return _asApiResult(
      await _fixture.deleteFixture(tournamentId: tournamentId),
    );
  }

  Future<CatalogData> fetchTournamentData(String tournamentId) async {
    return _orThrow(
      await _catalog.fetchTournamentData(tournamentId),
      'Error cargando datos del torneo',
    );
  }

  Future<CatalogData> fetchCatalogs(String tournamentId) async {
    return _orThrow(
      await _catalog.fetchCatalogs(tournamentId),
      'Error conectando al servidor',
    );
  }

  Future<int> createOfficial(
    String name,
    String role,
    String? signature,
  ) async {
    return _orThrow(
      await _officialVenue.createOfficial(name, role, signature),
      'Error creando oficial',
    );
  }

  Future<bool> deleteVenue(int id) async {
    return _asBool(await _officialVenue.deleteVenue(id));
  }

  Future<bool> deleteOfficial(int id) async {
    return _asBool(await _officialVenue.deleteOfficial(id));
  }

  Future<bool> updateOfficial({
    required String id,
    required String name,
    required String role,
    String? signature,
  }) async {
    return _asBool(
      await _officialVenue.updateOfficial(
        id: id,
        name: name,
        role: role,
        signature: signature,
      ),
    );
  }

  Future<Map<String, dynamic>> fetchFixture(String tournamentId) async {
    // Devolver {} ante un fallo replica el comportamiento anterior. Es una
    // perdida de informacion conocida: desaparece en la Fase 3.3.
    return (await _fixture.fetchFixture(tournamentId)).valueOrNull ?? {};
  }

  Future<int> createTeam(
    String name,
    String shortName,
    String coach, {
    String? tournamentId,
  }) async {
    return _orThrow(
      await _teams.createTeam(
        name,
        shortName,
        coach,
        tournamentId: tournamentId,
      ),
      'Error creando equipo',
    );
  }

  Future<int> addPlayer(int teamId, String name, int number) async {
    return _orThrow(
      await _teams.addPlayer(teamId, name, number),
      'Error agregando jugador',
    );
  }

  Future<bool> updateTeam({
    required String id,
    required String name,
    required String shortName,
    required String coachName,
  }) async {
    return _asBool(
      await _teams.updateTeam(
        id: id,
        name: name,
        shortName: shortName,
        coachName: coachName,
      ),
    );
  }

  Future<bool> updatePlayer(
    String id,
    int teamId,
    String name,
    int number,
  ) async {
    return _asBool(await _teams.updatePlayer(id, teamId, name, number));
  }

  Future<String> createTournament(String name, String category) async {
    return _orThrow(
      await _catalog.createTournament(name, category),
      'No se recibió el ID del torneo creado',
    );
  }

  // Obtiene los equipos y su estatus para el constructor manual
  Future<List<Map<String, dynamic>>> fetchTeamsSchedulingStatus(
    String tournamentId,
    int roundId,
  ) async {
    return (await _fixture.fetchTeamsSchedulingStatus(
          tournamentId,
          roundId,
        )).valueOrNull ??
        [];
  }

  Future<int?> addManualFixture({
    required String tournamentId,
    required int roundOrder,
    required int teamAId,
    required int teamBId,
  }) async {
    return (await _fixture.addManualFixture(
      tournamentId: tournamentId,
      roundOrder: roundOrder,
      teamAId: teamAId,
      teamBId: teamBId,
    )).valueOrNull;
  }

  Future<bool> deleteSingleFixture(int fixtureId) async {
    return _asBool(await _fixture.deleteSingleFixture(fixtureId));
  }

  Future<bool> syncMatchData(Map<String, dynamic> matchPayload) async {
    return _asBool(await _match.syncMatchData(matchPayload));
  }

  Future<bool> syncMatchDataMultipart({
    required Map<String, dynamic> matchData,
    required Uint8List? pdfBytes,
  }) async {
    return _asBool(
      await _match.syncMatchDataMultipart(
        matchData: matchData,
        pdfBytes: pdfBytes,
      ),
    );
  }

  Future<ApiResult> updateMatchAttendance({
    required String matchId,
    required List<Map<String, dynamic>> attendance,
  }) async {
    return ApiResult.from(
      await _match.updateMatchAttendance(
        matchId: matchId,
        attendance: attendance,
      ),
    );
  }

  Future<ApiResult> updateMatchOutcome({
    required String matchId,
    required String forfeitStatus,
    required String observaciones,
    String? signatureBase64,
    required int scoreA,
    required int scoreB,
    String? tournamentId,
    Uint8List? pdfBytes,
  }) async {
    return ApiResult.from(
      await _match.updateMatchOutcome(
        matchId: matchId,
        forfeitStatus: forfeitStatus,
        observaciones: observaciones,
        signatureBase64: signatureBase64,
        scoreA: scoreA,
        scoreB: scoreB,
        tournamentId: tournamentId,
        pdfBytes: pdfBytes,
      ),
    );
  }

  /// Consulta al backend el marcador REAL de un partido (suma de score_logs).
  /// Se usa al revertir un forfeit (20-0) al marcador jugado realmente,
  /// cuando los eventos ya no están en la BD local.
  ///
  /// [matchId] ID del partido a consultar.
  /// Retorna un record (scoreA, scoreB). Lanza Exception si la petición falla.
  Future<({int scoreA, int scoreB})> getRealScores(String matchId) async {
    return _orThrow(
      await _match.getRealScores(matchId),
      'Error obteniendo marcador real',
    );
  }

  /// Obtiene los datos del acta de un partido desde el backend.
  /// Se usa cuando la tabla matches local no tiene la fila (partido jugado
  /// en otro dispositivo). Retorna un Map con los campos del acta.
  Future<Map<String, dynamic>> getMatchDetails(String matchId) async {
    return _orThrow(
      await _match.getMatchDetails(matchId),
      'Error obteniendo datos del acta',
    );
  }

  /// Obtiene los eventos (score_logs) de un partido desde el backend.
  /// Se usa para hidratar gameEvents cuando el partido se jugó en otro dispositivo.
  Future<List<Map<String, dynamic>>> getMatchEvents(String matchId) async {
    return _orThrow(
      await _match.getMatchEvents(matchId),
      'Error obteniendo eventos',
    );
  }

  /// Obtiene el roster (match_rosters) de un partido desde el backend.
  /// Se usa para hidratar cuando el partido se jugó en otro dispositivo.
  Future<List<Map<String, dynamic>>> getMatchRosters(String matchId) async {
    return _orThrow(
      await _match.getMatchRosters(matchId),
      'Error obteniendo roster',
    );
  }
}
