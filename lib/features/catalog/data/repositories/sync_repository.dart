import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/database/daos/matches_dao.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/features/catalog/data/datasources/catalog_api.dart';
import 'package:myapp/features/fixture/data/datasources/fixture_api.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/data/datasources/official_venue_api.dart';
import 'package:myapp/features/teams/data/datasources/team_api.dart';
import 'package:myapp/features/catalog/domain/entities/sync_result.dart';
import 'package:myapp/features/match/domain/mappers/match_payload_mapper.dart';
import 'package:myapp/features/teams/data/repositories/player_repository.dart';

/// Orquesta la subida de datos pendientes a la nube.
///
/// Responsabilidad única: decidir QUÉ se sube y en QUÉ orden (las
/// dependencias de IDs importan), delegando la ejecución a los datasources y
/// a la base de datos. No conoce la UI: devuelve un [SyncResult].
///
/// El orden de subida respeta las dependencias de llaves foráneas:
/// jugadores offline → torneos → sedes → equipos → jugadores →
/// fixtures → partidos → oficiales.
class SyncRepository {
  final AppDatabase _db;
  final MatchesDao _matchesDao;
  final PlayerRepository _playerRepository;
  final CatalogApi _catalogApi;
  final OfficialVenueApi _officialVenueApi;
  final TeamApi _teamApi;
  final FixtureApi _fixtureApi;
  final MatchApi _matchApi;

  SyncRepository(
    this._db,
    this._matchesDao, {
    required PlayerRepository playerRepository,
    required CatalogApi catalogApi,
    required OfficialVenueApi officialVenueApi,
    required TeamApi teamApi,
    required FixtureApi fixtureApi,
    required MatchApi matchApi,
  }) : _playerRepository = playerRepository,
       _catalogApi = catalogApi,
       _officialVenueApi = officialVenueApi,
       _teamApi = teamApi,
       _fixtureApi = fixtureApi,
       _matchApi = matchApi;

  /// Desenvuelve o relanza.
  ///
  /// Cada bloque de subida ya vive dentro de un `try/catch` que registra y
  /// sigue con el siguiente elemento, asi que relanzar preserva el
  /// comportamiento. La diferencia es que ahora lo que viaja es una
  /// `AppException` tipada, no un string opaco.
  static T _unwrap<T>(Result<T> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };

  /// Punto de entrada único. Sube todo lo pendiente y devuelve el resumen.
  Future<SyncResult> uploadPendingData() async {
    // Reconcilia jugadores offline (IDs negativos) ANTES que nada, para
    // que ningún partido viaje con un playerId temporal.
    await _matchesDao.syncOfflinePlayersBeforeMatches(
      (teamId, name, number) async =>
          (await _teamApi.addPlayer(teamId, name, number)).valueOrNull,
    );

    var result = const SyncResult();

    result = result.copyWith(tournaments: await _uploadTournaments());
    result = result.copyWith(venues: await _uploadVenues());
    result = result.copyWith(teams: await _uploadTeams());
    result = result.copyWith(players: await _uploadPlayers());

    // _uploadFixtures devuelve el mapa {idViejo: idReal}; su .length = cuántos subió.
    final fixtureMap = await _uploadFixtures();
    result = result.copyWith(fixtures: fixtureMap.length);

    // _uploadMatches devuelve un record (int, List<String>): (subidos, omitidos).
    final matchOutcome = await _uploadMatches(fixtureMap);
    result = result.copyWith(
      matches: matchOutcome.$1,
      skippedMatches: matchOutcome.$2,
    );

    result = result.copyWith(officials: await _uploadOfficials());

    // Subir correcciones de asistencia pendientes (independiente de si hay
    // torneos/partidos nuevos: puede haber solo asistencias corregidas offline).
    await _uploadAttendanceCorrections();

    return result;
  }

  // =========================================================================
  // TORNEOS (migrado en Fase 1)
  // =========================================================================

  /// Sube torneos creados offline (UUID local) y reconcilia su ID por el
  /// real de la nube en las tablas hijas. Devuelve cuántos subió.
  Future<int> _uploadTournaments() async {
    int uploaded = 0;

    final pending = await (_db.select(
      _db.tournaments,
    )..where((tbl) => tbl.isSynced.equals(false))).get();

    for (final tourn in pending) {
      try {
        final realIdString = _unwrap(
          await _catalogApi.createTournament(
            tourn.name,
            tourn.category ?? 'Libre',
          ),
        );
        final String oldUuid = tourn.id;

        await _db.transaction(() async {
          await _db
              .into(_db.tournaments)
              .insert(
                TournamentsCompanion.insert(
                  id: Value(realIdString),
                  name: tourn.name,
                  category: Value(tourn.category),
                  status: const Value('ACTIVE'),
                  isSynced: const Value(true),
                ),
              );
          await (_db.update(
            _db.tournamentTeams,
          )..where((t) => t.tournamentId.equals(oldUuid))).write(
            TournamentTeamsCompanion(tournamentId: Value(realIdString)),
          );
          await (_db.update(_db.fixtures)
                ..where((f) => f.tournamentId.equals(oldUuid)))
              .write(FixturesCompanion(tournamentId: Value(realIdString)));
          await (_db.update(_db.matches)
                ..where((m) => m.tournamentId.equals(oldUuid)))
              .write(MatchesCompanion(tournamentId: Value(realIdString)));
          await (_db.delete(
            _db.tournaments,
          )..where((t) => t.id.equals(oldUuid))).go();
        });

        uploaded++;
      } catch (e) {
        debugPrint("Error subiendo torneo: $e");
      }
    }

    return uploaded;
  }

  // =========================================================================
  // SEDES (VENUES)
  // =========================================================================

  Future<int> _uploadVenues() async {
    int uploaded = 0;

    final pending = await (_db.select(
      _db.venues,
    )..where((tbl) => tbl.isSynced.equals(false))).get();

    for (final venue in pending) {
      try {
        final int? numericId = int.tryParse(venue.id);
        final bool isExisting = numericId != null && numericId > 0;

        // 1. Borrado lógico
        if (venue.name.startsWith('[DEL]-')) {
          if (isExisting) {
            final success = (await _officialVenueApi.deleteVenue(
              numericId,
            )).isOk;
            if (success) {
              await (_db.delete(
                _db.venues,
              )..where((v) => v.id.equals(venue.id))).go();
            }
          } else {
            await (_db.delete(
              _db.venues,
            )..where((v) => v.id.equals(venue.id))).go();
          }
          continue;
        }

        // 2. Actualización de sede existente
        if (isExisting) {
          final success = (await _officialVenueApi.updateVenue(
            id: venue.id,
            name: venue.name,
            address: venue.address ?? '',
          )).isOk;
          if (success) {
            await (_db.update(_db.venues)..where((v) => v.id.equals(venue.id)))
                .write(const VenuesCompanion(isSynced: Value(true)));
            uploaded++;
          }
        }
        // 3. Sede nueva
        else {
          final realIdInt = _unwrap(
            await _officialVenueApi.createVenue(
              venue.name,
              venue.address ?? '',
            ),
          );
          final String oldId = venue.id;

          await _db.transaction(() async {
            await _db
                .into(_db.venues)
                .insert(
                  VenuesCompanion.insert(
                    id: Value(realIdInt.toString()),
                    name: venue.name,
                    address: Value(venue.address),
                    isSynced: const Value(true),
                  ),
                  mode: InsertMode.insertOrReplace,
                );
            await (_db.update(_db.fixtures)
                  ..where((f) => f.venueId.equals(oldId)))
                .write(FixturesCompanion(venueId: Value(realIdInt.toString())));
            await (_db.update(_db.matches)
                  ..where((m) => m.venueId.equals(oldId)))
                .write(MatchesCompanion(venueId: Value(realIdInt.toString())));
            await (_db.delete(
              _db.venues,
            )..where((v) => v.id.equals(oldId))).go();
          });
          uploaded++;
        }
      } catch (e) {
        debugPrint("Error al sincronizar sede: $e");
      }
    }

    return uploaded;
  }

  // =========================================================================
  // EQUIPOS (TEAMS)
  // =========================================================================

  Future<int> _uploadTeams() async {
    int uploaded = 0;

    final pending = await (_db.select(
      _db.teams,
    )..where((tbl) => tbl.isSynced.equals(false))).get();

    for (final team in pending) {
      try {
        final isExistingTeam = (int.tryParse(team.id) ?? 0) > 0;

        // 1. Actualización offline
        if (isExistingTeam) {
          final success = (await _teamApi.updateTeam(
            id: team.id,
            name: team.name,
            shortName: team.shortName ?? '',
            coachName: team.coachName ?? '',
          )).isOk;
          if (success) {
            await (_db.update(_db.teams)..where((t) => t.id.equals(team.id)))
                .write(const TeamsCompanion(isSynced: Value(true)));
            uploaded++;
          }
        }
        // 2. Equipo nuevo creado offline
        else {
          final relation = await (_db.select(
            _db.tournamentTeams,
          )..where((t) => t.teamId.equals(team.id))).getSingleOrNull();
          final realIdInt = _unwrap(
            await _teamApi.createTeam(
              team.name,
              team.shortName ?? '',
              team.coachName ?? '',
              tournamentId: relation?.tournamentId,
            ),
          );
          final String oldTeamId = team.id;
          final String newTeamIdString = realIdInt.toString();

          await _db.transaction(() async {
            await _db
                .into(_db.teams)
                .insert(
                  TeamsCompanion.insert(
                    id: Value(newTeamIdString),
                    name: team.name,
                    shortName: Value(team.shortName),
                    coachName: Value(team.coachName),
                    isSynced: const Value(true),
                  ),
                );
            await (_db.update(
              _db.tournamentTeams,
            )..where((t) => t.teamId.equals(oldTeamId))).write(
              TournamentTeamsCompanion(teamId: Value(newTeamIdString)),
            );
            await (_db.update(_db.fixtures)
                  ..where((f) => f.teamAId.equals(oldTeamId)))
                .write(FixturesCompanion(teamAId: Value(newTeamIdString)));
            await (_db.update(_db.fixtures)
                  ..where((f) => f.teamBId.equals(oldTeamId)))
                .write(FixturesCompanion(teamBId: Value(newTeamIdString)));

            final tempTeamIdInt = int.tryParse(oldTeamId) ?? 0;
            await (_db.update(_db.players)
                  ..where((p) => p.teamId.equals(tempTeamIdInt)))
                .write(PlayersCompanion(teamId: Value(realIdInt)));
            await (_db.delete(
              _db.teams,
            )..where((t) => t.id.equals(oldTeamId))).go();
          });
          uploaded++;
        }
      } catch (e) {
        debugPrint("Error al subir equipo: $e");
      }
    }

    return uploaded;
  }

  // =========================================================================
  // JUGADORES (PLAYERS)
  // =========================================================================

  /// Delega en `PlayerRepository`: la misma subida la necesitaba tambien la
  /// pantalla de titulares, y las dos copias no eran equivalentes.
  Future<int> _uploadPlayers() => _playerRepository.uploadPendingPlayers();

  // =========================================================================
  // FIXTURES
  // =========================================================================

  /// Sube fixtures pendientes. Devuelve el mapa {idViejo: idNuevoReal}
  /// que los partidos necesitan para reasignar su fixtureId.
  Future<Map<String, String>> _uploadFixtures() async {
    final Map<String, String> fixtureMap = {};

    final pending = await (_db.select(
      _db.fixtures,
    )..where((tbl) => tbl.isSynced.equals(false))).get();

    for (final fixture in pending) {
      try {
        final int? numericId = int.tryParse(fixture.id);

        if (fixture.status == 'DELETED') {
          if (numericId != null) {
            final success = (await _fixtureApi.deleteSingleFixture(
              numericId,
            )).isOk;
            if (success) {
              await (_db.delete(
                _db.fixtures,
              )..where((f) => f.id.equals(fixture.id))).go();
            }
          } else {
            await (_db.delete(
              _db.fixtures,
            )..where((f) => f.id.equals(fixture.id))).go();
          }
          continue;
        }

        int roundOrder = 1;
        final matchRoundStr = RegExp(r'\d+').firstMatch(fixture.roundName);
        if (matchRoundStr != null) {
          roundOrder = int.parse(matchRoundStr.group(0)!);
        }

        String? newRealFixtureId;

        if (numericId != null) {
          final success = (await _fixtureApi.updateFixtureTeams(
            fixtureId: numericId,
            newTeamAId: int.tryParse(fixture.teamAId) ?? 0,
            newTeamBId: int.tryParse(fixture.teamBId) ?? 0,
          )).isOk;
          if (success) {
            newRealFixtureId = fixture.id;
            await (_db.update(_db.fixtures)
                  ..where((f) => f.id.equals(fixture.id)))
                .write(const FixturesCompanion(isSynced: Value(true)));
          }
        } else {
          final realIdInt = (await _fixtureApi.addManualFixture(
            tournamentId: fixture.tournamentId,
            roundOrder: roundOrder,
            teamAId: int.tryParse(fixture.teamAId) ?? 0,
            teamBId: int.tryParse(fixture.teamBId) ?? 0,
          )).valueOrNull;
          if (realIdInt != null) {
            newRealFixtureId = realIdInt.toString();
          }
        }

        if (newRealFixtureId != null) {
          fixtureMap[fixture.id] = newRealFixtureId;
        }
      } catch (e) {
        debugPrint("Error al subir fixture: $e");
      }
    }

    return fixtureMap;
  }

  // =========================================================================
  // PARTIDOS (MATCHES) — incluye el "escudo" anti IDs negativos
  // =========================================================================

  /// Sube partidos pendientes. Devuelve (cuántos subió, lista de omitidos).
  Future<(int, List<String>)> _uploadMatches(
    Map<String, String> fixtureMap,
  ) async {
    int uploaded = 0;
    final List<String> skipped = [];

    final pending = await (_db.select(
      _db.matches,
    )..where((tbl) => tbl.isSynced.equals(false))).get();

    for (final match in pending) {
      bool containsUnsyncedOfflinePlayers = false;

      final query = _db.select(_db.gameEvents).join([
        leftOuterJoin(
          _db.matchRosters,
          _db.matchRosters.matchId.equalsExp(_db.gameEvents.matchId) &
              _db.matchRosters.playerId.equalsExp(_db.gameEvents.playerId),
        ),
        leftOuterJoin(
          _db.players,
          _db.players.id.equalsExp(_db.gameEvents.playerId),
        ),
      ]);
      query.where(_db.gameEvents.matchId.equals(match.id));
      final rows = await query.get();

      final mapped = MatchPayloadMapper.mapEvents(
        rows.map(
          (row) => (
            event: row.readTable(_db.gameEvents),
            roster: row.readTableOrNull(_db.matchRosters),
            player: row.readTableOrNull(_db.players),
          ),
        ),
      );
      if (mapped.any((e) => e.isOfflinePlayer)) {
        containsUnsyncedOfflinePlayers = true;
      }
      final eventsList = mapped.map((e) => e.payload).toList();
      final playedIds = mapped
          .map((e) => e.playerId)
          .whereType<int>()
          .toSet();

      Uint8List? savedPdfBytes;
      if (match.matchReportPath != null && match.matchReportPath!.isNotEmpty) {
        try {
          final file = File(match.matchReportPath!);
          if (await file.exists()) savedPdfBytes = await file.readAsBytes();
        } catch (e) {
          debugPrint("No se pudo leer el PDF local: $e");
        }
      }

      final rosterRows = await (_db.select(
        _db.matchRosters,
      )..where((r) => r.matchId.equals(match.id))).get();

      final rostersList = rosterRows.map((r) {
        final playerId = int.tryParse(r.playerId) ?? 0;
        if (playerId < 0) containsUnsyncedOfflinePlayers = true;
        final forfeited = MatchPayloadMapper.teamForfeited(
          r.teamSide,
          match.forfeitStatus,
        );
        return MatchPayloadMapper.mapRoster(
          r,
          playerId: playerId,
          // En la subida diferida ya no hay estadisticas en memoria: que un
          // jugador haya jugado se deduce de aparecer en algun evento.
          hasPlayed: !forfeited && playedIds.contains(playerId),
        );
      }).toList();

      if (containsUnsyncedOfflinePlayers) {
        debugPrint(
          "ESCUDO ACTIVO: omitido ${match.teamAName} vs ${match.teamBName} (jugadores no sincronizados).",
        );
        skipped.add("${match.teamAName} vs ${match.teamBName}");
        continue;
      }

      final String? mappedFixtureId =
          fixtureMap[match.fixtureId] ?? match.fixtureId;
      final matchPayload = {
        "match_id": match.id,
        "fixture_id": mappedFixtureId,
        "tournament_id": match.tournamentId,
        "venue_id": match.venueId,
        "team_a_id": match.teamAId,
        "team_b_id": match.teamBId,
        "team_a_name": match.teamAName,
        "team_b_name": match.teamBName,
        "score_a": match.scoreA,
        "score_b": match.scoreB,
        "current_period": 4,
        "time_left": "00:00",
        "main_referee": match.mainReferee,
        "aux_referee": match.auxReferee,
        "scorekeeper": match.scorekeeper,
        "signature_base64": match.signatureData,
        "status": match.status,
        "forfeit_status": match.forfeitStatus,
        "observaciones": match.observaciones,
        "match_date": match.matchDate == null
            ? null
            : MatchPayloadMapper.backendDateTime(match.matchDate!),
        "events": eventsList,
        "rosters": rostersList,
      };

      final success = (await _matchApi.syncMatchDataMultipart(
        matchData: matchPayload,
        pdfBytes: savedPdfBytes,
      )).isOk;
      if (success) {
        await (_db.update(_db.matches)..where((tbl) => tbl.id.equals(match.id)))
            .write(const MatchesCompanion(isSynced: Value(true)));
        uploaded++;
      }
    }

    return (uploaded, skipped);
  }

  // =========================================================================
  // OFICIALES (OFFICIALS)
  // =========================================================================

  Future<int> _uploadOfficials() async {
    int uploaded = 0;

    final pending = await (_db.select(
      _db.officials,
    )..where((tbl) => tbl.isSynced.equals(false))).get();

    for (final official in pending) {
      try {
        final int? numericId = int.tryParse(official.id.toString());
        final bool isExisting = numericId != null && numericId > 0;

        if (official.name.startsWith('[DEL]-')) {
          if (isExisting) {
            final success = (await _officialVenueApi.deleteOfficial(
              numericId,
            )).isOk;
            if (success) {
              await (_db.delete(
                _db.officials,
              )..where((o) => o.id.equals(official.id.toString()))).go();
            }
          } else {
            await (_db.delete(
              _db.officials,
            )..where((o) => o.id.equals(official.id.toString()))).go();
          }
          continue;
        }

        if (isExisting) {
          final success = (await _officialVenueApi.updateOfficial(
            id: official.id.toString(),
            name: official.name,
            role: official.role,
            signature: official.signatureData,
          )).isOk;
          if (success) {
            await (_db.update(_db.officials)
                  ..where((o) => o.id.equals(official.id.toString())))
                .write(const OfficialsCompanion(isSynced: Value(true)));
            uploaded++;
          }
        } else {
          final realIdInt = _unwrap(
            await _officialVenueApi.createOfficial(
              official.name,
              official.role,
              official.signatureData ?? '',
            ),
          );
          final String oldId = official.id.toString();

          await _db.transaction(() async {
            await _db
                .into(_db.officials)
                .insert(
                  OfficialsCompanion.insert(
                    id: realIdInt.toString(),
                    name: official.name,
                    role: Value(official.role),
                    signatureData: Value(official.signatureData),
                    active: const Value(true),
                    isSynced: const Value(true),
                  ),
                  mode: InsertMode.insertOrReplace,
                );
            await (_db.delete(
              _db.officials,
            )..where((o) => o.id.equals(oldId))).go();
          });
          uploaded++;
        }
      } catch (e) {
        debugPrint("Error al sincronizar oficial: $e");
      }
    }

    return uploaded;
  }

  /// Sube las correcciones de asistencia pendientes (rosters con isSynced=false)
  /// agrupadas por partido, vía el endpoint de asistencia.
  Future<int> _uploadAttendanceCorrections() async {
    final pending = await (_db.select(
      _db.matchRosters,
    )..where((r) => r.isSynced.equals(false))).get();
    if (pending.isEmpty) return 0;

    // Agrupar por match_id.
    final Map<String, List<Map<String, dynamic>>> byMatch = {};
    for (final r in pending) {
      byMatch.putIfAbsent(r.matchId, () => []).add({
        "player_id": int.tryParse(r.playerId) ?? 0,
        "attended": r.attended ? 1 : 0,
      });
    }

    int synced = 0;
    for (final entry in byMatch.entries) {
      final result = await _matchApi.updateMatchAttendance(
        matchId: entry.key,
        attendance: entry.value,
      );
      if (result.isOk) {
        // Marcar esos rosters como sincronizados.
        await (_db.update(_db.matchRosters)..where(
              (r) => r.matchId.equals(entry.key) & r.isSynced.equals(false),
            ))
            .write(const MatchRostersCompanion(isSynced: Value(true)));
        synced++;
      }
    }
    return synced;
  }
}
