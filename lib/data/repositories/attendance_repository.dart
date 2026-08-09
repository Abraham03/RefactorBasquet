import 'package:myapp/core/models/catalog_models.dart';
import 'package:myapp/core/database/daos/matches_dao.dart';
import 'package:myapp/core/network/api_service.dart';
import 'package:myapp/core/network/result.dart';

/// Corrección de asistencia de partidos finalizados. Persiste localmente y
/// sincroniza a la nube. Reusa el DAO de asistencia de la Fase 1 (DRY).
class AttendanceRepository {
  final MatchesDao _dao;
  final ApiService _api;

  AttendanceRepository(this._dao, this._api);

  Future<List<RosterWithName>> getRoster(String matchId) => _dao.getRosterWithNames(matchId);

  /// Guarda cambios de asistencia: primero local (fuente de verdad offline),
  /// luego intenta la nube. Devuelve el resultado de la nube.
  Future<ApiResult> saveAttendance(String matchId, Map<String, bool> byPlayerId) async {
    // 1. Local siempre (offline-first).
    await _dao.setAttendanceBatch(matchId, byPlayerId);

    // 2. Nube (si falla, queda local y se puede reintentar).
    final list = byPlayerId.entries
        .map((e) => {"player_id": int.tryParse(e.key) ?? 0, "attended": e.value ? 1 : 0})
        .toList();
    return _api.updateMatchAttendance(matchId: matchId, attendance: list);
  }
}