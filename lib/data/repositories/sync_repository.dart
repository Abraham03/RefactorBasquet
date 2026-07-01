import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../core/database/app_database.dart';
import '../../core/database/daos/matches_dao.dart';
import '../../core/service/api_service.dart';
import '../../core/models/sync_result.dart';

/// Orquesta la subida de datos pendientes a la nube.
///
/// Responsabilidad única: decidir QUÉ se sube y en QUÉ orden (las
/// dependencias de IDs importan), delegando la ejecución a ApiService y
/// a la base de datos. No conoce la UI: devuelve un [SyncResult].
///
/// El orden de subida respeta las dependencias de llaves foráneas:
/// jugadores offline → torneos → sedes → equipos → jugadores →
/// fixtures → partidos → oficiales.
class SyncRepository {
  final AppDatabase _db;
  final ApiService _api;
  final MatchesDao _matchesDao;

  SyncRepository(this._db, this._api, this._matchesDao);


  /// Punto de entrada único. Sube todo lo pendiente y devuelve el resumen.
  Future<SyncResult> uploadPendingData() async {
    // Reconcilia jugadores offline (IDs negativos) ANTES que nada, para
    // que ningún partido viaje con un playerId temporal.
    await _matchesDao.syncOfflinePlayersBeforeMatches(_api);

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

    return result;
  }

  // =========================================================================
  // TORNEOS (migrado en Fase 1)
  // =========================================================================

  /// Sube torneos creados offline (UUID local) y reconcilia su ID por el
  /// real de la nube en las tablas hijas. Devuelve cuántos subió.
  Future<int> _uploadTournaments() async {
    int uploaded = 0;

    final pending = await (_db.select(_db.tournaments)
          ..where((tbl) => tbl.isSynced.equals(false)))
        .get();

    for (final tourn in pending) {
      try {
        final realIdString =
            await _api.createTournament(tourn.name, tourn.category ?? 'Libre');
        final String oldUuid = tourn.id;

        await _db.transaction(() async {
          await _db.into(_db.tournaments).insert(
                TournamentsCompanion.insert(
                  id: Value(realIdString),
                  name: tourn.name,
                  category: Value(tourn.category),
                  status: const Value('ACTIVE'),
                  isSynced: const Value(true),
                ),
              );
          await (_db.update(_db.tournamentTeams)
                ..where((t) => t.tournamentId.equals(oldUuid)))
              .write(TournamentTeamsCompanion(tournamentId: Value(realIdString)));
          await (_db.update(_db.fixtures)
                ..where((f) => f.tournamentId.equals(oldUuid)))
              .write(FixturesCompanion(tournamentId: Value(realIdString)));
          await (_db.update(_db.matches)
                ..where((m) => m.tournamentId.equals(oldUuid)))
              .write(MatchesCompanion(tournamentId: Value(realIdString)));
          await (_db.delete(_db.tournaments)
                ..where((t) => t.id.equals(oldUuid)))
              .go();
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

    final pending = await (_db.select(_db.venues)
          ..where((tbl) => tbl.isSynced.equals(false)))
        .get();

    for (final venue in pending) {
      try {
        final int? numericId = int.tryParse(venue.id);
        final bool isExisting = numericId != null && numericId > 0;

        // 1. Borrado lógico
        if (venue.name.startsWith('[DEL]-')) {
          if (isExisting) {
            final success = await _api.deleteVenue(numericId);
            if (success) {
              await (_db.delete(_db.venues)..where((v) => v.id.equals(venue.id))).go();
            }
          } else {
            await (_db.delete(_db.venues)..where((v) => v.id.equals(venue.id))).go();
          }
          continue;
        }

        // 2. Actualización de sede existente
        if (isExisting) {
          final success = await _api.updateVenue(
              id: venue.id, name: venue.name, address: venue.address ?? '');
          if (success) {
            await (_db.update(_db.venues)..where((v) => v.id.equals(venue.id)))
                .write(const VenuesCompanion(isSynced: Value(true)));
            uploaded++;
          }
        }
        // 3. Sede nueva
        else {
          final realIdInt = await _api.createVenue(venue.name, venue.address ?? '');
          final String oldId = venue.id;

          await _db.transaction(() async {
            await _db.into(_db.venues).insert(
                  VenuesCompanion.insert(
                    id: Value(realIdInt.toString()),
                    name: venue.name,
                    address: Value(venue.address),
                    isSynced: const Value(true),
                  ),
                  mode: InsertMode.insertOrReplace,
                );
            await (_db.update(_db.fixtures)..where((f) => f.venueId.equals(oldId)))
                .write(FixturesCompanion(venueId: Value(realIdInt.toString())));
            await (_db.update(_db.matches)..where((m) => m.venueId.equals(oldId)))
                .write(MatchesCompanion(venueId: Value(realIdInt.toString())));
            await (_db.delete(_db.venues)..where((v) => v.id.equals(oldId))).go();
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

    final pending = await (_db.select(_db.teams)
          ..where((tbl) => tbl.isSynced.equals(false)))
        .get();

    for (final team in pending) {
      try {
        final isExistingTeam = (int.tryParse(team.id) ?? 0) > 0;

        // 1. Actualización offline
        if (isExistingTeam) {
          final success = await _api.updateTeam(
            id: team.id,
            name: team.name,
            shortName: team.shortName ?? '',
            coachName: team.coachName ?? '',
          );
          if (success) {
            await (_db.update(_db.teams)..where((t) => t.id.equals(team.id)))
                .write(const TeamsCompanion(isSynced: Value(true)));
            uploaded++;
          }
        }
        // 2. Equipo nuevo creado offline
        else {
          final relation = await (_db.select(_db.tournamentTeams)
                ..where((t) => t.teamId.equals(team.id)))
              .getSingleOrNull();
          final realIdInt = await _api.createTeam(
            team.name, team.shortName ?? '', team.coachName ?? '',
            tournamentId: relation?.tournamentId,
          );
          final String oldTeamId = team.id;
          final String newTeamIdString = realIdInt.toString();

          await _db.transaction(() async {
            await _db.into(_db.teams).insert(
                  TeamsCompanion.insert(
                    id: Value(newTeamIdString),
                    name: team.name,
                    shortName: Value(team.shortName),
                    coachName: Value(team.coachName),
                    isSynced: const Value(true),
                  ),
                );
            await (_db.update(_db.tournamentTeams)
                  ..where((t) => t.teamId.equals(oldTeamId)))
                .write(TournamentTeamsCompanion(teamId: Value(newTeamIdString)));
            await (_db.update(_db.fixtures)..where((f) => f.teamAId.equals(oldTeamId)))
                .write(FixturesCompanion(teamAId: Value(newTeamIdString)));
            await (_db.update(_db.fixtures)..where((f) => f.teamBId.equals(oldTeamId)))
                .write(FixturesCompanion(teamBId: Value(newTeamIdString)));

            final tempTeamIdInt = int.tryParse(oldTeamId) ?? 0;
            await (_db.update(_db.players)..where((p) => p.teamId.equals(tempTeamIdInt)))
                .write(PlayersCompanion(teamId: Value(realIdInt)));
            await (_db.delete(_db.teams)..where((t) => t.id.equals(oldTeamId))).go();
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

  Future<int> _uploadPlayers() async {
    int uploaded = 0;

    final pending = await (_db.select(_db.players)
          ..where((tbl) => tbl.isSynced.equals(false)))
        .get();

    // Truco anti-deadlock: despeja dorsales a +1000 en la nube primero.
    for (final player in pending) {
      final isExistingPlayer = (int.tryParse(player.id) ?? 0) > 0;
      if (isExistingPlayer) {
        try {
          await _api.updatePlayer(
              player.id, player.teamId, player.name, player.defaultNumber + 1000);
        } catch (_) {}
      }
    }

    for (final player in pending) {
      try {
        final isExistingPlayer = (int.tryParse(player.id) ?? 0) > 0;

        if (isExistingPlayer) {
          final success = await _api.updatePlayer(
              player.id, player.teamId, player.name, player.defaultNumber);
          if (success) {
            await (_db.update(_db.players)..where((p) => p.id.equals(player.id)))
                .write(const PlayersCompanion(isSynced: Value(true)));
            uploaded++;
          }
        } else {
          final realPlayerId =
              await _api.addPlayer(player.teamId, player.name, player.defaultNumber);
          final String realIdStr = realPlayerId.toString();
          final String oldIdStr = player.id;

          await _db.transaction(() async {
            await _db.into(_db.players).insert(
                  PlayersCompanion.insert(
                    id: Value(realIdStr),
                    teamId: player.teamId,
                    name: player.name,
                    defaultNumber: Value(player.defaultNumber),
                    isSynced: const Value(true),
                    active: const Value(true),
                  ),
                );
            await (_db.update(_db.gameEvents)..where((e) => e.playerId.equals(oldIdStr)))
                .write(GameEventsCompanion(playerId: Value(realIdStr)));
            await (_db.update(_db.matchRosters)..where((r) => r.playerId.equals(oldIdStr)))
                .write(MatchRostersCompanion(playerId: Value(realIdStr)));
            await (_db.delete(_db.players)..where((p) => p.id.equals(oldIdStr))).go();
          });

          // Limpieza de IDs embebidos en el texto de los SUB.
          final allEvents = await _db.select(_db.gameEvents).get();
          for (final ev in allEvents) {
            if (ev.type.contains(oldIdStr)) {
              final newType = ev.type.replaceAll(oldIdStr, realIdStr);
              await (_db.update(_db.gameEvents)
                    ..where((e) =>
                        e.matchId.equals(ev.matchId) & e.type.equals(ev.type)))
                  .write(GameEventsCompanion(type: Value(newType)));
            }
          }

          uploaded++;
        }
      } catch (e) {
        debugPrint("Error al subir jugador: $e");
      }
    }

    return uploaded;
  }

  // =========================================================================
  // FIXTURES
  // =========================================================================

  /// Sube fixtures pendientes. Devuelve el mapa {idViejo: idNuevoReal}
  /// que los partidos necesitan para reasignar su fixtureId.
  Future<Map<String, String>> _uploadFixtures() async {
    final Map<String, String> fixtureMap = {};

    final pending = await (_db.select(_db.fixtures)
          ..where((tbl) => tbl.isSynced.equals(false)))
        .get();

    for (final fixture in pending) {
      try {
        final int? numericId = int.tryParse(fixture.id);

        if (fixture.status == 'DELETED') {
          if (numericId != null) {
            final success = await _api.deleteSingleFixture(numericId);
            if (success) {
              await (_db.delete(_db.fixtures)..where((f) => f.id.equals(fixture.id))).go();
            }
          } else {
            await (_db.delete(_db.fixtures)..where((f) => f.id.equals(fixture.id))).go();
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
          final success = await _api.updateFixtureTeams(
            fixtureId: numericId,
            newTeamAId: int.tryParse(fixture.teamAId) ?? 0,
            newTeamBId: int.tryParse(fixture.teamBId) ?? 0,
          );
          if (success) {
            newRealFixtureId = fixture.id;
            await (_db.update(_db.fixtures)..where((f) => f.id.equals(fixture.id)))
                .write(const FixturesCompanion(isSynced: Value(true)));
          }
        } else {
          final realIdInt = await _api.addManualFixture(
            tournamentId: fixture.tournamentId,
            roundOrder: roundOrder,
            teamAId: int.tryParse(fixture.teamAId) ?? 0,
            teamBId: int.tryParse(fixture.teamBId) ?? 0,
          );
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
  Future<(int, List<String>)> _uploadMatches(Map<String, String> fixtureMap) async {
    int uploaded = 0;
    final List<String> skipped = [];

    final pending = await (_db.select(_db.matches)
          ..where((tbl) => tbl.isSynced.equals(false)))
        .get();

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

      int runningScoreA = 0;
      int runningScoreB = 0;

      final eventsList = rows.map((row) {
        final event = row.readTable(_db.gameEvents);
        final roster = row.readTableOrNull(_db.matchRosters);
        final player = row.readTableOrNull(_db.players);
        String rawType = event.type;
        String teamSide = roster?.teamSide ?? 'A';
        if (rawType.endsWith('_A')) {
          teamSide = 'A';
          rawType = rawType.replaceAll('_A', '');
        } else if (rawType.endsWith('_B')) {
          teamSide = 'B';
          rawType = rawType.replaceAll('_B', '');
        }
        int points = 0;
        if (rawType == 'POINT_1' || rawType == 'FREE_THROW') points = 1;
        if (rawType == 'POINT_2') points = 2;
        if (rawType == 'POINT_3') points = 3;
        bool isTeamA = teamSide == 'A';
        if (points > 0) {
          if (isTeamA) {
            runningScoreA += points;
          } else {
            runningScoreB += points;
          }
        }
        final currentScore = isTeamA ? runningScoreA : runningScoreB;

        final Map<String, dynamic> eventPayload = {
          "period": event.period,
          "team_side": teamSide,
          "player_name": player?.name ?? '',
          "player_number": roster?.jerseyNumber ?? 0,
          "points_scored": points,
          "score_after": currentScore,
          "type": rawType,
        };

        int pId = 0;
        if (event.playerId != null &&
            event.playerId!.isNotEmpty &&
            event.playerId != '-1') {
          pId = int.tryParse(event.playerId!) ?? 0;
        }
        if (pId < 0) containsUnsyncedOfflinePlayers = true;
        eventPayload["player_id"] = (pId > 0) ? pId : null;
        return eventPayload;
      }).toList();

      Uint8List? savedPdfBytes;
      if (match.matchReportPath != null && match.matchReportPath!.isNotEmpty) {
        try {
          final file = File(match.matchReportPath!);
          if (await file.exists()) savedPdfBytes = await file.readAsBytes();
        } catch (e) {
          debugPrint("No se pudo leer el PDF local: $e");
        }
      }

      final rosterRows = await (_db.select(_db.matchRosters)
            ..where((r) => r.matchId.equals(match.id)))
          .get();
      final rostersList = rosterRows.map((r) {
        final pIdInt = int.tryParse(r.playerId) ?? 0;
        if (pIdInt < 0) containsUnsyncedOfflinePlayers = true;
        final hasPlayed = eventsList.any((event) => event["player_id"] == pIdInt);
        return {
          "player_id": pIdInt,
          "team_side": r.teamSide,
          "jersey_number": r.jerseyNumber,
          "is_captain": r.isCaptain ? 1 : 0,
          "played": hasPlayed ? 1 : 0
        };
      }).toList();

      if (containsUnsyncedOfflinePlayers) {
        debugPrint(
            "ESCUDO ACTIVO: omitido ${match.teamAName} vs ${match.teamBName} (jugadores no sincronizados).");
        skipped.add("${match.teamAName} vs ${match.teamBName}");
        continue;
      }

      final String? mappedFixtureId = fixtureMap[match.fixtureId] ?? match.fixtureId;
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
        "events": eventsList,
        "rosters": rostersList,
      };

      final success = await _api.syncMatchDataMultipart(
        matchData: matchPayload,
        pdfBytes: savedPdfBytes,
      );
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

    final pending = await (_db.select(_db.officials)
          ..where((tbl) => tbl.isSynced.equals(false)))
        .get();

    for (final official in pending) {
      try {
        final int? numericId = int.tryParse(official.id.toString());
        final bool isExisting = numericId != null && numericId > 0;

        if (official.name.startsWith('[DEL]-')) {
          if (isExisting) {
            final success = await _api.deleteOfficial(numericId);
            if (success) {
              await (_db.delete(_db.officials)
                    ..where((o) => o.id.equals(official.id.toString())))
                  .go();
            }
          } else {
            await (_db.delete(_db.officials)
                  ..where((o) => o.id.equals(official.id.toString())))
                .go();
          }
          continue;
        }

        if (isExisting) {
          final success = await _api.updateOfficial(
            id: official.id.toString(),
            name: official.name,
            role: official.role,
            signature: official.signatureData,
          );
          if (success) {
            await (_db.update(_db.officials)
                  ..where((o) => o.id.equals(official.id.toString())))
                .write(const OfficialsCompanion(isSynced: Value(true)));
            uploaded++;
          }
        } else {
          final realIdInt = await _api.createOfficial(
            official.name,
            official.role,
            official.signatureData ?? '',
          );
          final String oldId = official.id.toString();

          await _db.transaction(() async {
            await _db.into(_db.officials).insert(
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
            await (_db.delete(_db.officials)..where((o) => o.id.equals(oldId))).go();
          });
          uploaded++;
        }
      } catch (e) {
        debugPrint("Error al sincronizar oficial: $e");
      }
    }

    return uploaded;
  }

}