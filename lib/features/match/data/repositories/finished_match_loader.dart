import 'package:drift/drift.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/errors/app_exception.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/core/utils/json_parsing.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/domain/entities/match_restore_snapshot.dart';
import 'package:myapp/features/match/domain/repositories/official_repository_contract.dart';
import 'package:myapp/features/match/domain/services/outcome_changer.dart';
import 'package:myapp/core/constants/match_status.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';

/// Lo que necesita la pantalla de "cambiar resultado" para arrancar.
class PreparedMatch {
  final MatchRestoreSnapshot snapshot;
  final OutcomePdfParams pdfParams;
  final String matchId;
  final String teamAName;
  final String teamBName;

  const PreparedMatch({
    required this.snapshot,
    required this.pdfParams,
    required this.matchId,
    required this.teamAName,
    required this.teamBName,
  });
}

/// Datos del acta, vengan de la BD local o del backend.
class _ActaHeader {
  final String matchId;
  final String teamAName;
  final String teamBName;
  final String mainReferee;
  final String auxReferee;
  final String scorekeeper;
  final DateTime? matchDate;
  final String? tournamentId;
  final int teamAId;
  final int teamBId;
  final String? venueId;

  const _ActaHeader({
    required this.matchId,
    required this.teamAName,
    required this.teamBName,
    required this.mainReferee,
    required this.auxReferee,
    required this.scorekeeper,
    required this.matchDate,
    required this.tournamentId,
    required this.teamAId,
    required this.teamBId,
    required this.venueId,
  });
}

/// Prepara un partido **ya finalizado** para poder corregir su resultado.
///
/// Era un `onTap` de ~250 líneas dentro de un `ListTile` de un bottom sheet:
/// llamada al backend, seis consultas a drift, dos upserts idénticos a
/// `matches`, hidratación de rosters y eventos, restauración del controller y
/// navegación. Todo en un solo closure, sin un test posible.
///
/// El caso de uso hace el trabajo; la pantalla se queda con el `switch` sobre
/// el `Result`, el mensaje y el `Navigator`.
/// Reune todo lo necesario para reabrir un partido ya finalizado y corregir
/// su resultado: la cabecera del acta, los rosters y los eventos, tirando de
/// la nube cuando el partido se jugo en otro dispositivo.
///
/// **Vivia en `domain/usecases/`, y no era su sitio.** No tiene ninguna regla
/// de negocio: solo decide DE DONDE sacar cada dato y lo deja hidratado en
/// local. Ademas recibe un `Fixture` generado por drift. Eso es la capa de
/// datos, no el dominio, y por estar mal colocado obligaba a `domain/` a
/// importar drift (regla 3 del plan).
class FinishedMatchLoader {
  FinishedMatchLoader(this._db, this._api, this._officials);

  final AppDatabase _db;
  final MatchApi _api;
  final OfficialRepositoryContract _officials;

  Future<Result<PreparedMatch>> call(Fixture fixture) async {
    final header = await _loadHeader(fixture);
    if (header case Err(:final error)) return Err(error);
    final acta = (header as Ok<_ActaHeader>).value;

    // La fila `matches` es FK de rosters y eventos. Antes se insertaba DOS
    // veces con el mismo contenido, en dos ramas distintas del closure.
    await _ensureMatchRow(acta);

    final tournament = await (_db.select(
      _db.tournaments,
    )..where((t) => t.id.equals(acta.tournamentId ?? ''))).getSingleOrNull();

    final players = await _db.select(_db.players).get();
    List<CatalogPlayer> rosterFor(int teamId) => players
        .where((p) => p.teamId == teamId)
        .map(
          (p) => CatalogPlayer(
            id: tryParseId(p.id) ?? -1,
            name: p.name,
            teamId: p.teamId,
            defaultNumber: p.defaultNumber,
          ),
        )
        .toList();

    final rosters = await _rostersForActa(acta.matchId);
    await _hydrateEventsIfMissing(acta.matchId);

    final signatures = await _officials.getRefereeSignatures(
      mainRefereeName: acta.mainReferee,
      auxRefereeName: acta.auxReferee,
    );

    final teamA = await (_db.select(
      _db.teams,
    )..where((t) => t.id.equals('${acta.teamAId}'))).getSingleOrNull();
    final teamB = await (_db.select(
      _db.teams,
    )..where((t) => t.id.equals('${acta.teamBId}'))).getSingleOrNull();

    final captainA = rosters
        .where((r) => r.teamSide == TeamSide.home && r.isCaptain)
        .firstOrNull;
    final captainB = rosters
        .where((r) => r.teamSide == TeamSide.away && r.isCaptain)
        .firstOrNull;

    Set<int> startersOf(String side) => rosters
        .where((r) => r.teamSide == side && r.isStarter)
        .map((r) => tryParseId(r.playerId) ?? -1)
        .where((id) => id > 0)
        .toSet();

    return Ok(
      PreparedMatch(
        matchId: acta.matchId,
        teamAName: acta.teamAName,
        teamBName: acta.teamBName,
        snapshot: MatchRestoreSnapshot(
          matchId: acta.matchId,
          fixtureId: fixture.id,
          rosterA: rosterFor(acta.teamAId),
          rosterB: rosterFor(acta.teamBId),
          startersA: startersOf('A'),
          startersB: startersOf('B'),
          tournamentId: tryParseId(acta.tournamentId) ?? 0,
          venueId: tryParseId(acta.venueId) ?? 0,
          teamAId: acta.teamAId,
          teamBId: acta.teamBId,
          mainReferee: acta.mainReferee,
          auxReferee: acta.auxReferee,
          scorekeeper: acta.scorekeeper,
        ),
        pdfParams: OutcomePdfParams(
          teamAName: acta.teamAName,
          teamBName: acta.teamBName,
          tournamentName: tournament?.name ?? '',
          categoryName: tournament?.category ?? '',
          tournamentLogoUrl: tournament?.logoUrl ?? '',
          refereeLogoUrl: tournament?.refereeLogoUrl ?? '',
          venueName: fixture.venueName ?? '',
          mainReferee: acta.mainReferee,
          auxReferee: acta.auxReferee,
          scorekeeper: acta.scorekeeper,
          coachA: teamA?.coachName ?? '',
          coachB: teamB?.coachName ?? '',
          captainAId: tryParseId(captainA?.playerId),
          captainBId: tryParseId(captainB?.playerId),
          matchDate: acta.matchDate,
          mainRefSignature: signatures.main,
          auxRefSignature: signatures.aux,
          tournamentId: acta.tournamentId,
        ),
      ),
    );
  }

  /// El acta sale de la fila local si el partido se jugó en este dispositivo;
  /// si no, del backend (online-only).
  Future<Result<_ActaHeader>> _loadHeader(Fixture fixture) async {
    final linkedId = fixture.matchId;
    var local = (linkedId != null && linkedId.isNotEmpty)
        ? await (_db.select(
            _db.matches,
          )..where((t) => t.id.equals(linkedId))).getSingleOrNull()
        : null;
    local ??= await (_db.select(
      _db.matches,
    )..where((t) => t.fixtureId.equals(fixture.id))).getSingleOrNull();

    if (local != null) {
      return Ok(
        _ActaHeader(
          matchId: local.id,
          teamAName: local.teamAName,
          teamBName: local.teamBName,
          mainReferee: local.mainReferee ?? '',
          auxReferee: local.auxReferee ?? '',
          scorekeeper: local.scorekeeper ?? '',
          matchDate: local.matchDate,
          tournamentId: local.tournamentId,
          teamAId: local.teamAId ?? 0,
          teamBId: local.teamBId ?? 0,
          venueId: local.venueId,
        ),
      );
    }

    final remoteId = fixture.matchId ?? fixture.id;
    final details = await _api.getMatchDetails(remoteId);
    if (details case Err(:final error)) return Err(error);
    final d = (details as Ok<Map<String, dynamic>>).value;

    return Ok(
      _ActaHeader(
        matchId: d['id']?.toString() ?? remoteId,
        teamAName: d['team_a_name']?.toString() ?? fixture.teamAName,
        teamBName: d['team_b_name']?.toString() ?? fixture.teamBName,
        mainReferee: d['main_referee']?.toString() ?? '',
        auxReferee: d['aux_referee']?.toString() ?? '',
        scorekeeper: d['scorekeeper']?.toString() ?? '',
        matchDate: DateTime.tryParse(d['match_date']?.toString() ?? ''),
        tournamentId: d['tournament_id']?.toString(),
        teamAId: tryParseId(d['team_a_id']) ?? 0,
        teamBId: tryParseId(d['team_b_id']) ?? 0,
        venueId: d['venue_id']?.toString(),
      ),
    );
  }

  /// Garantiza la fila `matches`: es FK de `matchRosters` y `gameEvents`.
  ///
  /// Se marca `FINISHED` para no alterar el estado del calendario.
  Future<void> _ensureMatchRow(_ActaHeader acta) {
    return _db
        .into(_db.matches)
        .insertOnConflictUpdate(
          MatchesCompanion.insert(
            id: Value(acta.matchId),
            teamAName: acta.teamAName,
            teamBName: acta.teamBName,
            status: const Value(MatchStatus.finished),
            tournamentId: Value(acta.tournamentId),
            venueId: Value(acta.venueId),
            teamAId: Value(acta.teamAId),
            teamBId: Value(acta.teamBId),
            mainReferee: Value(acta.mainReferee),
            auxReferee: Value(acta.auxReferee),
            scorekeeper: Value(acta.scorekeeper),
            matchDate: Value(acta.matchDate),
            isSynced: const Value(true),
          ),
        );
  }

  /// Roster del acta. Si no hay local, se baja de la nube: el partido se jugó
  /// en otro dispositivo y sin él no habría capitanes ni titulares.
  Future<List<RosterEntry>> _rostersForActa(String matchId) async {
    Future<List<RosterEntry>> read() => (_db.select(
      _db.matchRosters,
    )..where((t) => t.matchId.equals(matchId))).get();

    final local = await read();
    if (local.isNotEmpty) return local;

    final cloud = await _api.getMatchRosters(matchId);
    if (cloud case Err()) {
      // Sin roster el acta sale sin capitanes ni titulares, pero el resto del
      // flujo sigue siendo útil: no se aborta.
      return local;
    }

    for (final r in (cloud as Ok<List<Map<String, dynamic>>>).value) {
      await _db
          .into(_db.matchRosters)
          .insertOnConflictUpdate(
            MatchRostersCompanion.insert(
              matchId: matchId,
              playerId: r['player_id'].toString(),
              teamSide: r['team_side'].toString(),
              jerseyNumber: parseIntOrNull(r['jersey_number']) ?? 0,
              isCaptain: Value(parseBool(r['is_captain'])),
              isStarter: Value(parseBool(r['is_starter'])),
              attended: Value(parseBool(r['attended'])),
            ),
          );
    }
    return read();
  }

  /// Baja las jugadas de la nube si no hay ninguna local, para que el acta en
  /// PDF salga con marcador Y jugadas.
  Future<void> _hydrateEventsIfMissing(String matchId) async {
    final local = await (_db.select(
      _db.gameEvents,
    )..where((t) => t.matchId.equals(matchId))).get();
    if (local.isNotEmpty) return;

    final cloud = await _api.getMatchEvents(matchId);
    if (cloud case Err()) {
      // El PDF saldrá con marcador pero sin jugadas.
      return;
    }

    final events = (cloud as Ok<List<Map<String, dynamic>>>).value;
    final base = DateTime.now();

    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      final rawType = e['event_type']?.toString() ?? '';
      final points = parseIntOrNull(e['points_scored']) ?? 0;
      // Eventos antiguos no traen `event_type`: al menos se conserva la
      // anotación.
      final type = rawType.isNotEmpty
          ? rawType
          : (points > 0 ? 'POINT_$points' : 'OTROS');

      final rawPlayerId = e['player_id']?.toString();
      final playerId =
          (rawPlayerId == null || rawPlayerId.isEmpty || rawPlayerId == '0')
          ? null
          : rawPlayerId;

      final clockTime = e['clock_time']?.toString();

      await _db
          .into(_db.gameEvents)
          .insert(
            GameEventsCompanion.insert(
              matchId: matchId,
              type: type,
              period: parseIntOrNull(e['period']) ?? 1,
              clockTime: (clockTime == null || clockTime.isEmpty)
                  ? '00:00'
                  : clockTime,
              playerId: Value(playerId),
              // Preserva el orden original de las jugadas.
              createdAt: Value(base.add(Duration(milliseconds: i))),
              isSynced: const Value(true),
            ),
          );
    }
  }
}

/// Alias para no arrastrar `AppException` en los imports de quien solo usa el
/// caso de uso.
typedef OpenMatchFailure = AppException;
