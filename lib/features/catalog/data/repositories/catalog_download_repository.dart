import 'package:drift/drift.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/errors/app_exception.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/features/catalog/data/datasources/catalog_api.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_download.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';
import 'package:myapp/core/constants/match_status.dart';
import 'package:myapp/shared/services/image_loader_service.dart';
import 'package:myapp/shared/services/image_store.dart';

/// Sincronización de **bajada**: descarga el catálogo de la nube y reemplaza
/// el local.
///
/// Es la contraparte de [SyncRepository], que hace la subida. Vivía dentro de
/// `home_menu_screen._syncData()`, 270 líneas mezcladas con un diálogo de
/// confirmación, un loader y tres SnackBars — imposible de probar sin montar
/// la pantalla entera.
///
/// La pantalla conserva lo que le corresponde: preguntar al usuario y mostrar
/// el resultado. Aquí solo queda el QUÉ se descarga y en qué orden.
class CatalogDownloadRepository {
  /// [logoCache] es opcional: sin él la descarga funciona igual, solo que los
  /// logos del acta se bajarán la primera vez que se genere una con red.
  CatalogDownloadRepository(this._db, this._api, {ImageStore? logoCache})
    : _logoCache = logoCache;

  final AppDatabase _db;
  final CatalogApi _api;
  final ImageStore? _logoCache;

  /// Partidos que aún no se han subido.
  ///
  /// La descarga los borra, así que la pantalla usa esto para avisar antes de
  /// destruir trabajo del usuario.
  Future<List<BasketballMatch>> pendingMatches() {
    return (_db.select(
      _db.matches,
    )..where((m) => m.isSynced.equals(false))).get();
  }

  /// Descarga el catálogo del torneo y reemplaza el local.
  ///
  /// Todo el borrado y la reinserción van dentro de **una sola transacción**:
  /// si algo falla a mitad, la base queda como estaba en vez de medio vacía.
  Future<Result<CatalogDownloadSummary>> downloadAll(
    String tournamentId,
  ) async {
    final fetched = await _api.fetchCatalogs(tournamentId);
    if (fetched case Err(:final error)) {
      return Err(error);
    }
    final data = (fetched as Ok<CatalogData>).value;

    try {
      await _db.transaction(() async {
        await _deleteGhostMatches();
        await _wipeCatalogs();
        await _insertAll(data);
      });
    } catch (e) {
      // Un fallo de esquema (p.ej. un nombre que excede el CHECK de longitud)
      // reventaba como excepción suelta y la pantalla, que solo contempla
      // Ok/Err, no podía informar de nada. La transacción ya revirtió.
      return Err(StorageException(cause: e));
    }

    await _warmLogos(data.tournaments);

    return Ok(
      CatalogDownloadSummary(
        tournaments: data.tournaments.length,
        teams: data.teams.length,
        players: data.players.length,
        venues: data.venues.length,
        fixtures: data.fixtures.length,
        officials: data.officials.length,
        finishedRosters: data.finishedRosters.length,
      ),
    );
  }

  /// Deja los logos del acta en disco aprovechando que aquí **sí** hay red.
  ///
  /// Va fuera de la transacción a propósito: son descargas, y mantenerlas
  /// dentro tendría la base bloqueada durante toda la espera de red. Tampoco
  /// afecta al resultado — un logo que no se pudo precargar solo significa
  /// que se intentará de nuevo al generar el acta.
  Future<void> _warmLogos(List<CatalogTournament> tournaments) async {
    final cache = _logoCache;
    if (cache == null) return;

    for (final t in tournaments) {
      // `refresh` porque el backend puede cambiar el escudo dejando la misma
      // URL; sin esto el acta seguiría imprimiendo el anterior para siempre.
      await PdfImageLoader.warmCache(t.logoUrl, cache, refresh: true);
      await PdfImageLoader.warmCache(t.refereeLogoUrl, cache, refresh: true);
    }
  }

  /// Borra los partidos a medio jugar y todo lo que cuelga de ellos.
  ///
  /// Los `FINISHED` **se conservan**: la nube no los vuelve a mandar y con
  /// ellos se perdería su historial (rosters, asistencia, eventos).
  Future<void> _deleteGhostMatches() async {
    final ghosts = await (_db.select(
      _db.matches,
    )..where((m) => m.status.equals(MatchStatus.finished).not())).get();
    final ids = ghosts.map((m) => m.id).toList();
    if (ids.isEmpty) return;

    await (_db.delete(
      _db.matchRosters,
    )..where((r) => r.matchId.isIn(ids))).go();
    await (_db.delete(_db.gameEvents)..where((e) => e.matchId.isIn(ids))).go();
    await (_db.delete(_db.matches)..where((m) => m.id.isIn(ids))).go();
  }

  Future<void> _wipeCatalogs() async {
    await _db.delete(_db.tournaments).go();
    await _db.delete(_db.teams).go();
    await _db.delete(_db.players).go();
    await _db.delete(_db.tournamentTeams).go();
    await _db.delete(_db.venues).go();
    await _db.delete(_db.fixtures).go();
    await _db.delete(_db.officials).go();
  }

  Future<void> _insertAll(CatalogData data) async {
    for (final t in data.tournaments) {
      await _upsert(
        _db.tournaments,
        TournamentsCompanion.insert(
          id: Value(t.id.toString()),
          name: t.name,
          category: Value(t.category),
          status: Value(t.status ?? 'ACTIVE'),
          logoUrl: Value(t.logoUrl),
          refereeLogoUrl: Value(t.refereeLogoUrl),
          isSynced: const Value(true),
        ),
      );
    }

    for (final f in data.fixtures) {
      await _upsert(
        _db.fixtures,
        FixturesCompanion.insert(
          id: f.id,
          tournamentId: f.tournamentId,
          roundName: f.roundName,
          teamAId: f.teamAId,
          teamBId: f.teamBId,
          teamAName: f.teamAName,
          teamBName: f.teamBName,
          logoA: Value(f.logoA),
          logoB: Value(f.logoB),
          venueId: Value(f.venueId),
          venueName: Value(f.venueName),
          scheduledDatetime: Value(f.scheduledDatetime),
          matchId: Value(f.matchId),
          scoreA: Value(f.scoreA),
          scoreB: Value(f.scoreB),
          status: Value(f.status),
        ),
      );
    }

    for (final team in data.teams) {
      await _upsert(
        _db.teams,
        TeamsCompanion.insert(
          id: Value(team.id.toString()),
          name: team.name,
          shortName: Value(team.shortName),
          coachName: Value(team.coachName),
          logoUrl: Value(team.logoUrl),
          isSynced: const Value(true),
        ),
      );
    }

    for (final venue in data.venues) {
      await _upsert(
        _db.venues,
        VenuesCompanion.insert(
          id: Value(venue.id.toString()),
          name: venue.name,
          address: Value(venue.address),
          isSynced: const Value(true),
        ),
      );
    }

    for (final rel in data.relationships) {
      await _upsert(
        _db.tournamentTeams,
        TournamentTeamsCompanion.insert(
          tournamentId: rel.tournamentId.toString(),
          teamId: rel.teamId.toString(),
          isSynced: const Value(true),
        ),
      );
    }

    for (final p in data.players) {
      await _upsert(
        _db.players,
        PlayersCompanion.insert(
          id: Value(p.id.toString()),
          name: p.name,
          teamId: p.teamId,
          defaultNumber: Value(p.defaultNumber),
          active: const Value(true),
          isSynced: const Value(true),
          photoUrl: Value(p.photoUrl),
        ),
      );
    }

    // Rosters de partidos ya finalizados: permiten corregir la asistencia de
    // un partido que se jugó en otro dispositivo.
    for (final r in data.finishedRosters) {
      await _upsert(
        _db.matchRosters,
        MatchRostersCompanion.insert(
          matchId: r.matchId,
          playerId: r.playerId,
          teamSide: r.teamSide,
          jerseyNumber: r.jerseyNumber,
          isCaptain: Value(r.isCaptain),
          attended: Value(r.attended),
          isSynced: const Value(true),
        ),
      );
    }

    for (final off in data.officials) {
      await _upsert(
        _db.officials,
        OfficialsCompanion.insert(
          id: off.id,
          name: off.name,
          role: Value(off.role),
          signatureData: Value(off.signature),
          active: const Value(true),
          isSynced: const Value(true),
        ),
      );
    }
  }

  Future<void> _upsert<T extends Table, D>(
    TableInfo<T, D> table,
    Insertable<D> row,
  ) {
    return _db.into(table).insert(row, mode: InsertMode.insertOrReplace);
  }
}
