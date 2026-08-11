import 'package:drift/drift.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/errors/app_exception.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/core/utils/json_parsing.dart';
import 'package:myapp/features/fixture/data/datasources/fixture_api.dart';
import 'package:myapp/core/constants/match_status.dart';

/// Calendario local: descarga desde la nube y consultas derivadas.
///
/// La bajada + reinserción estaba copiada en `fixture_list_screen` y en
/// `manual_fixture_builder_screen`, y **las dos copias no eran iguales**: la
/// primera no marcaba `isSynced`, así que los partidos recién bajados de la
/// nube quedaban como "pendientes de subir" y la siguiente sincronización los
/// reenviaba al servidor. Ver [refresh].
class FixtureRepository {
  FixtureRepository(this._db, this._api);

  final AppDatabase _db;
  final FixtureApi _api;

  /// Reemplaza el calendario local del torneo por el de la nube.
  ///
  /// Devuelve cuántos partidos quedaron guardados.
  ///
  /// El borrado y la reinserción van **dentro de la misma transacción**: en
  /// las copias anteriores el `delete` quedaba fuera, así que un fallo a mitad
  /// dejaba al usuario sin calendario.
  Future<Result<int>> refresh(String tournamentId) async {
    final fetched = await _api.fetchFixture(tournamentId);
    if (fetched case Err(:final error)) return Err(error);

    final rounds = _roundsOf((fetched as Ok<Map<String, dynamic>>).value);
    if (rounds == null) {
      // El torneo aún no tiene calendario: no es un error, pero tampoco hay
      // que borrar lo que haya en local.
      return const Ok(0);
    }

    var saved = 0;
    try {
      await _db.transaction(() async {
        await (_db.delete(
          _db.fixtures,
        )..where((f) => f.tournamentId.equals(tournamentId))).go();

        for (final round in rounds.entries) {
          for (final raw in (round.value as List)) {
            final m = raw as Map<String, dynamic>;
            await _db
                .into(_db.fixtures)
                .insert(
                  FixturesCompanion.insert(
                    id: m['id'].toString(),
                    tournamentId: tournamentId,
                    // El nombre de la jornada es la CLAVE del mapa, no un
                    // campo del partido.
                    roundName: round.key,
                    teamAId: m['team_a_id'].toString(),
                    teamBId: m['team_b_id'].toString(),
                    teamAName: m['team_a'] as String? ?? 'A',
                    teamBName: m['team_b'] as String? ?? 'B',
                    logoA: Value(m['logo_a'] as String?),
                    logoB: Value(m['logo_b'] as String?),
                    status: Value(
                      m['status'] as String? ?? MatchStatus.scheduled,
                    ),
                    // Viene de la nube: ya está sincronizado. Omitirlo lo
                    // dejaba en `false` (el default) y la siguiente subida lo
                    // reenviaba al servidor como si fuera un cambio local.
                    isSynced: const Value(true),
                  ),
                  mode: InsertMode.insertOrReplace,
                );
            saved++;
          }
        }
      });
    } catch (e) {
      return Err(StorageException(cause: e));
    }

    return Ok(saved);
  }

  /// Parejas (local, visitante) ya programadas, para contar enfrentamientos.
  ///
  /// Se lee de la nube porque el constructor manual necesita el estado real
  /// aunque el local esté desactualizado. Los cancelados no cuentan.
  Future<Result<List<(int, int)>>> scheduledTeamPairs(
    String tournamentId,
  ) async {
    final fetched = await _api.fetchFixture(tournamentId);
    if (fetched case Err(:final error)) return Err(error);

    final rounds = _roundsOf((fetched as Ok<Map<String, dynamic>>).value);
    if (rounds == null) return const Ok([]);

    final pairs = <(int, int)>[];
    for (final round in rounds.entries) {
      for (final raw in (round.value as List)) {
        final m = raw as Map<String, dynamic>;
        if (m['status'] == MatchStatus.cancelled) continue;

        final teamA = tryParseId(m['team_a_id']) ?? 0;
        final teamB = tryParseId(m['team_b_id']) ?? 0;
        if (teamA != 0 && teamB != 0) pairs.add((teamA, teamB));
      }
    }
    return Ok(pairs);
  }

  /// El endpoint devuelve `{rounds: {"Jornada 1": [...], ...}}`, o nada si el
  /// torneo todavía no tiene calendario.
  static Map<String, dynamic>? _roundsOf(Map<String, dynamic> data) {
    final rounds = data['rounds'];
    return rounds is Map<String, dynamic> ? rounds : null;
  }
}
