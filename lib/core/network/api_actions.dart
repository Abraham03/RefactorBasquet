/// Las 30 acciones del backend PHP, en un solo sitio.
///
/// El servidor es un endpoint único (`api.php`) enrutado por `?action=`. Estos
/// literales estaban repartidos por los 30 métodos de `ApiService`, así que un
/// typo solo se descubría en producción y no había forma de enumerarlos.
///
/// **Invariante I2 del plan:** estos valores son el contrato con el backend.
/// Cambiar uno rompe la app contra el servidor en producción. Los goldens de
/// `test/core/network/api_contract_golden_test.dart` los vigilan.
library;

abstract final class ApiActions {
  // --- Torneos ---
  static const String getTournamentsList = 'get_tournaments_list';
  static const String createTournament = 'create_tournament';
  static const String saveTournamentRules = 'save_tournament_rules';
  static const String getTournamentData = 'get_tournament_data';
  static const String getSyncData = 'get_sync_data';

  // --- Sedes ---
  static const String createVenue = 'create_venue';
  static const String updateVenue = 'update_venue';
  static const String deleteVenue = 'delete_venue';

  // --- Oficiales ---
  static const String createOfficial = 'create_official';
  static const String updateOfficial = 'update_official';
  static const String deleteOfficial = 'delete_official';

  // --- Equipos y jugadores ---
  static const String createTeam = 'create_team';
  static const String updateTeam = 'update_team';
  static const String addPlayer = 'add_player';
  static const String updatePlayer = 'update_player';

  // --- Calendario ---
  static const String generateFixture = 'generate_fixture';
  static const String deleteFixture = 'delete_fixture';
  static const String getFixture = 'get_fixture';
  static const String updateFixtureTeams = 'update_fixture_teams';
  static const String syncManualFixtures = 'sync_manual_fixtures';
  static const String addManualFixture = 'add_manual_fixture';
  static const String deleteSingleFixture = 'delete_single_fixture';
  static const String getTeamSchedulingStatus = 'get_team_scheduling_status';

  // --- Partido ---
  static const String syncMatch = 'sync_match';
  static const String getMatchDetails = 'get_match_details';
  static const String getMatchEvents = 'get_match_events';
  static const String getMatchRosters = 'get_match_rosters';
  static const String getRealScores = 'get_real_scores';
  static const String updateMatchAttendance = 'update_match_attendance';
  static const String updateMatchOutcome = 'update_match_outcome';

  /// Todas las acciones. La usa el test de contrato para comprobar que cada
  /// una tiene su golden.
  static const Set<String> all = {
    getTournamentsList,
    createTournament,
    saveTournamentRules,
    getTournamentData,
    getSyncData,
    createVenue,
    updateVenue,
    deleteVenue,
    createOfficial,
    updateOfficial,
    deleteOfficial,
    createTeam,
    updateTeam,
    addPlayer,
    updatePlayer,
    generateFixture,
    deleteFixture,
    getFixture,
    updateFixtureTeams,
    syncManualFixtures,
    addManualFixture,
    deleteSingleFixture,
    getTeamSchedulingStatus,
    syncMatch,
    getMatchDetails,
    getMatchEvents,
    getMatchRosters,
    getRealScores,
    updateMatchAttendance,
    updateMatchOutcome,
  };
}
