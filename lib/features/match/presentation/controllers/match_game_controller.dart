import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/database/daos/matches_dao.dart';
import 'package:myapp/core/di/providers.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
import 'package:myapp/features/match/domain/engines/game_clock.dart';
import 'package:myapp/features/match/domain/engines/match_clock_format.dart';
import 'package:myapp/features/match/domain/engines/match_history.dart';
import 'package:myapp/features/match/domain/engines/score_engine.dart';
import 'package:myapp/features/match/domain/engines/substitution_engine.dart';
import 'package:myapp/features/match/domain/engines/timeout_engine.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:flutter/foundation.dart';
import 'package:myapp/features/teams/data/datasources/team_api.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/domain/entities/match_restore_snapshot.dart';
import 'package:myapp/features/match/domain/mappers/match_payload_mapper.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/core/utils/id_generator.dart';
import 'package:myapp/features/match/domain/repositories/match_finalization_port.dart';

class MatchGameController extends StateNotifier<MatchState>
    implements MatchFinalizationPort {
  final MatchesDao _dao;

  /// El reloj de juego. Se inyecta para poder acelerarlo en los tests: antes
  /// era un `Timer?` suelto, imposible de sustituir.
  final GameClock _clock;
  bool _isFinished = false;
  final MatchHistory _history = MatchHistory();

  MatchGameController(this._dao, {GameClock? clock})
    : _clock = clock ?? GameClock(),
      super(const MatchState());

  int getTeamFouls(String teamId) => teamFoulsOf(state, teamId);

/// Reconstruye un partido ya jugado a partir de su [MatchRestoreSnapshot].
///
/// Recibia estos 13 valores como parametros sueltos y dos pantallas los
/// armaban por separado: cualquiera podia olvidar uno o cruzar `teamAId` con
/// `teamBId` sin que nada fallara al compilar (Parameter Object).
Future<void> restoreFromDatabase(
  MatchRestoreSnapshot snapshot, {
  bool markFinished = false,
}) async {
  final matchId = snapshot.matchId;
  final fixtureId = snapshot.fixtureId;
  final rosterA = snapshot.rosterA;
  final rosterB = snapshot.rosterB;
  final startersA = snapshot.startersA;
  final startersB = snapshot.startersB;
  final tournamentId = snapshot.tournamentId;
  final venueId = snapshot.venueId;
  final teamAId = snapshot.teamAId;
  final teamBId = snapshot.teamBId;
  final mainReferee = snapshot.mainReferee;
  final auxReferee = snapshot.auxReferee;
  final scorekeeper = snapshot.scorekeeper;

    _isFinished = markFinished;
  // 1. Inicializar usando los starters que vienen del widget (los que elegiste en la pantalla de selección)
  // Si startersA viene vacío desde el calendario, entonces el problema está en el paso de datos del FixtureList.
  initializeNewMatch(
    matchId: matchId,
    fixtureId: fixtureId,
    rosterA: rosterA,
    rosterB: rosterB,
    startersA: startersA, 
    startersB: startersB,
    tournamentId: tournamentId,
    venueId: venueId,
    teamAId: teamAId,
    teamBId: teamBId,
    mainReferee: mainReferee,
    auxReferee: auxReferee,
    scorekeeper: scorekeeper,
  );

  // 1b. SEMBRAR JUGADORES QUE NO VIENEN EN EL ROSTER DE LA NUBE
  //     (creados offline a mitad de partido). Están en matchRosters y en la tabla
  //     local 'players', pero NO en rosterA/rosterB, así que initializeNewMatch
  //     no los creó. Sin esto, un jugador offline que solo entró por cambio se pierde.
  final seedRosters = await (_dao.db.select(_dao.db.matchRosters)
        ..where((tbl) => tbl.matchId.equals(matchId))).get();

  final seededStats = Map<String, PlayerStats>.from(state.playerStats);
  final seededBenchA = List<String>.from(state.teamABench);
  final seededBenchB = List<String>.from(state.teamBBench);

  for (final r in seedRosters) {
    if (seededStats.containsKey(r.playerId)) continue; // ya existe (titular o banca de nube)

    final local = await (_dao.db.select(_dao.db.players)
          ..where((p) => p.id.equals(r.playerId))).getSingleOrNull();

    seededStats[r.playerId] = PlayerStats(
      dbId: int.tryParse(r.playerId) ?? 0,
      playerName: local?.name ?? "Jugador ${r.jerseyNumber}",
      playerNumber: r.jerseyNumber.toString(),
      isStarter: false,
      isOnCourt: false,
      hasPlayed: false,
    );

    if (r.teamSide == 'A') {
      if (!seededBenchA.contains(r.playerId)) seededBenchA.add(r.playerId);
    } else {
      if (!seededBenchB.contains(r.playerId)) seededBenchB.add(r.playerId);
    }
  }

  state = state.copyWith(
    playerStats: seededStats,
    teamABench: seededBenchA,
    teamBBench: seededBenchB,
  );

  // 2. RECUPERAR CAPITANES Y MARCAR "HAS PLAYED"
  final dbRosters = await (_dao.db.select(_dao.db.matchRosters)
        ..where((tbl) => tbl.matchId.equals(matchId))).get();

  Map<String, PlayerStats> statsWithCaptains = Map.from(state.playerStats);
  for (var row in dbRosters) {
    if (row.isCaptain) {
      statsWithCaptains.forEach((name, pStat) {
        if (pStat.dbId.toString() == row.playerId) {
          statsWithCaptains[name] = pStat.copyWith(hasPlayed: true);
        }
      });
    }
  }
  state = state.copyWith(playerStats: statsWithCaptains);

  // 2b. RESTAURAR TITULARES desde la columna isStarter de matchRosters.
  final starterStats = Map<String, PlayerStats>.from(state.playerStats);
  final courtA = List<String>.from(state.teamAOnCourt);
  final benchA = List<String>.from(state.teamABench);
  final courtB = List<String>.from(state.teamBOnCourt);
  final benchB = List<String>.from(state.teamBBench);

  for (final r in dbRosters) {           // dbRosters ya se consultó en el paso 2
    if (!r.isStarter) continue;
    if (starterStats.containsKey(r.playerId)) {
      starterStats[r.playerId] = starterStats[r.playerId]!
          .copyWith(isStarter: true, isOnCourt: true, hasPlayed: true);
    }
    if (r.teamSide == 'A') {
      benchA.remove(r.playerId);
      if (!courtA.contains(r.playerId)) courtA.add(r.playerId);
    } else {
      benchB.remove(r.playerId);
      if (!courtB.contains(r.playerId)) courtB.add(r.playerId);
    }
  }

  state = state.copyWith(
    playerStats: starterStats,
    teamAOnCourt: courtA, teamABench: benchA,
    teamBOnCourt: courtB, teamBBench: benchB,
  );

  // 3. PROCESAR EVENTOS (Aquí es donde los jugadores "suben" a cancha si hubo cambios o puntos)
  final events = await (_dao.db.select(_dao.db.gameEvents)
        ..where((tbl) => tbl.matchId.equals(matchId))
        ..orderBy([(t) => drift.OrderingTerm.asc(t.createdAt)]))
      .get();

  // 4. Procesar eventos acumulativamente
    for (var event in events) {

      // --- REPLAY DE CAMBIOS (SUB): el ID vive en 'type', no en playerId ---
      // Reconstruye cancha/banca y marca "entró a jugar" al jugador entrante.
      if (event.type.startsWith('SUB_')) {
        final m = RegExp(r'^SUB_([AB])_OUT_(.+?)_IN_(.+)$').firstMatch(event.type);
        if (m != null) {
          _applyRestoreSub(
            teamId: m.group(1)!,
            outId: m.group(2)!,
            inId: m.group(3)!,
            period: event.period,
          );
        }
        continue;
      }

      // reconstruye las listas teamATimeouts1/2/OT (y B) y termina la
      // iteración con 'continue' para que no caiga en la lógica de abajo.
      if (EventType.isTimeout(event.type)) {
        final toTeam = event.type.endsWith('_B') ? 'B' : 'A';
        _applyRestoreTimeout(toTeam, event.period, event.clockTime);
        continue;
      }

      // --- POSESIÓN: el último evento POSS_ define la flecha actual ---
      if (event.type.startsWith('POSS_')) {
        final p = event.type.substring(5); // 'A', 'B' o 'NONE'
        state = state.copyWith(possession: p == 'NONE' ? '' : p);
        continue;
      }

      String teamId = 'A';
      String? pName;
      String pNumber = "00";
      int dbId = 0;
      String pIdKey = event.playerId ?? "-1";

      if (event.playerId != null && event.playerId != "-1") {
        final pA = rosterA.where((p) => p.id.toString() == event.playerId).firstOrNull;
        final pB = rosterB.where((p) => p.id.toString() == event.playerId).firstOrNull;
        
        if (pB != null) { teamId = 'B'; pName = pB.name; pNumber = pB.defaultNumber.toString(); dbId = pB.id; }
        else if (pA != null) { teamId = 'A'; pName = pA.name; pNumber = pA.defaultNumber.toString(); dbId = pA.id; }
        else {
          // --- Buscar en SQLite para rescatar a los jugadores offline creados localmente ---
          final localPlayer = await (_dao.db.select(_dao.db.players)..where((p) => p.id.equals(event.playerId!))).getSingleOrNull();
          if (localPlayer != null) {
            teamId = localPlayer.teamId == teamAId ? 'A' : 'B';
            pName = localPlayer.name;
            pNumber = localPlayer.defaultNumber.toString(); // <--- Aquí rescatamos el numero
            dbId = int.tryParse(localPlayer.id) ?? 0;
          }
        }
      } else if (event.type.endsWith('_B')) { 
        teamId = 'B'; pIdKey = "Banca_$teamId";
      } else if (event.type.endsWith('_C')) {
        teamId = 'C'; pIdKey = "Coach_$teamId";
      } else if (EventType.isTimeout(event.type)) {
        pIdKey = "TIMEOUT_$teamId";
      }

      int pts = 0;
      if (event.type == 'POINT_1') {pts = 1;}
      else if (event.type == 'POINT_2') {pts = 2;}
      else if (event.type == 'POINT_3') {pts = 3;}

      int fls = (pts == 0 && EventType.isPlayerFoul(event.type)) ? 1 : 0;

      _applyRestoreEvent(
        teamId: teamId,
        playerId: pIdKey, // Pasamos el ID exacto
        playerName: pName ?? (EventType.isTimeout(event.type) ? "TIMEOUT" : "OTROS"),
        points: pts,
        fouls: fls,
        type: event.type,
        period: event.period,
        pNumber: pNumber,
        dbPlayerId: dbId,
        clockTime: event.clockTime,
      );
    }

    // 5. RESTAURAR RELOJ Y PERIODO desde el último evento registrado.
  final matchRow = await _dao.getMatchById(matchId);
  if (matchRow != null) {
      final restored = MatchClockFormat.parse(matchRow.clockTime);
      final mm = restored.inMinutes;
      final ss = restored.inSeconds % 60;
      state = state.copyWith(
        timeLeft: Duration(minutes: mm, seconds: ss),
        currentPeriod: matchRow.currentPeriod,
        isRunning: false,
      );
    } else if (events.isNotEmpty) {
      // Respaldo: partidos viejos sin reloj persistido en 'matches'.
      final last = events.last;
      final parts = last.clockTime.split(':');
      if (parts.length == 2) {
        final mm = int.tryParse(parts[0].trim()) ?? 10;
        final ss = int.tryParse(parts[1].trim()) ?? 0;
        state = state.copyWith(
          timeLeft: Duration(minutes: mm, seconds: ss),
          currentPeriod: last.period,
          isRunning: false,
        );
      }
    }

}

// Reconstruye un tiempo muerto durante el restore, respetando los topes por
// sección (2 en cuartos 1-2, 3 en cuartos 3-4, 3 en extras). El marcador del
// minuto se deriva del reloj guardado del evento (clockTime, ej. "04:59" -> "4").
// Nota: el "X" de quema automática en clutch no se reconstruye (depende del reloj
// en vivo, no de un evento), por lo que es una aproximación fiel a lo registrado.
void _applyRestoreTimeout(String teamId, int period, String clockTime) {
  String minStr = clockTime.split(':').first.trim();
  if (minStr.startsWith('0') && minStr.length > 1) minStr = minStr.substring(1);
  if (minStr.isEmpty) minStr = "0";

  if (period <= 2) {
    final list = List<String>.from(teamId == 'A' ? state.teamATimeouts1 : state.teamBTimeouts1);
    if (list.length < 2) list.add(minStr);
    state = teamId == 'A'
        ? state.copyWith(teamATimeouts1: list)
        : state.copyWith(teamBTimeouts1: list);
  } else if (period == 3 || period == 4) {
    final list = List<String>.from(teamId == 'A' ? state.teamATimeouts2 : state.teamBTimeouts2);
    if (list.length < 3) list.add(minStr);
    state = teamId == 'A'
        ? state.copyWith(teamATimeouts2: list)
        : state.copyWith(teamBTimeouts2: list);
  } else {
    final list = List<String>.from(teamId == 'A' ? state.teamAOTTimeouts : state.teamBOTTimeouts);
    if (list.length < 3) list.add(minStr);
    state = teamId == 'A'
        ? state.copyWith(teamAOTTimeouts: list)
        : state.copyWith(teamBOTTimeouts: list);
  }
}

// Método auxiliar necesario para el restore
// Método auxiliar necesario para el restore
void _applyRestoreEvent({
  required String teamId,
  required String playerId,
  required String playerName,
  required int points,
  required int fouls,
  required String type,
  required int period,
  required String pNumber,
  required int dbPlayerId,
  String clockTime = "0:00",
}) {
  // Ahora usamos playerId para la llave del mapa (como dicta el resto de la app)
  final currentStats = state.playerStats[playerId] ?? PlayerStats(
    dbId: dbPlayerId,
    playerName: playerName,
    playerNumber: pNumber,
  );

  final newPlayerStatsMap = Map<String, PlayerStats>.from(state.playerStats);

  // Solo tocamos estadísticas en eventos REALES de punto o falta de un jugador.
  // Coach (C_x), Banca (B_x) y TIMEOUT no son jugadores y no deben crear entradas.
  // CLAVE POR ID (playerId), nunca por nombre: así coincide con cancha/banca y el PDF.
  if (points > 0 || fouls > 0) {
    List<String> newFoulDetails = List.from(currentStats.foulDetails);
    if (fouls > 0) newFoulDetails.add(type);

    newPlayerStatsMap[playerId] = currentStats.copyWith(
      points: currentStats.points + points,
      fouls: currentStats.fouls + fouls,
      foulDetails: newFoulDetails,
      hasPlayed: true,
    );
  }

  int newScoreA = state.scoreA + (teamId == 'A' ? points : 0);
  int newScoreB = state.scoreB + (teamId == 'B' ? points : 0);

  final newScoreLog = List<ScoreEvent>.from(state.scoreLog);
  newScoreLog.add(ScoreEvent(
    period: period, teamId: teamId,
    playerId: playerId,
    dbPlayerId: dbPlayerId,
    playerNumber: pNumber, points: points, scoreAfter: teamId == 'A' ? newScoreA : newScoreB, type: type,
  ));

  final newPeriodScores = Map<int, List<int>>.from(state.periodScores);
  if (!newPeriodScores.containsKey(period)) {
    newPeriodScores[period] = [0, 0];
  }
  newPeriodScores[period]![teamId == 'A' ? 0 : 1] += points;

  state = state.copyWith(
    playerStats: newPlayerStatsMap,
    scoreA: newScoreA,
    scoreB: newScoreB,
    scoreLog: newScoreLog,
    periodScores: newPeriodScores,
    currentPeriod: period,
  );
}


// Re-aplica un cambio durante el restore: mueve jugadores entre cancha/banca,
// marca "entró a jugar" y reinyecta un evento 'SUB' limpio en el scoreLog
// (mismo formato que usa la app en vivo, para que el undo siga funcionando).
void _applyRestoreSub({
  required String teamId,
  required String outId,
  required String inId,
  required int period,
}) {
  final newStats = Map<String, PlayerStats>.from(state.playerStats);
  if (newStats.containsKey(outId)) {
    newStats[outId] = newStats[outId]!.copyWith(isOnCourt: false, hasPlayed: true);
  }
  if (newStats.containsKey(inId)) {
    newStats[inId] = newStats[inId]!.copyWith(isOnCourt: true, hasPlayed: true);
  }

  final court = List<String>.from(teamId == 'A' ? state.teamAOnCourt : state.teamBOnCourt);
  final bench = List<String>.from(teamId == 'A' ? state.teamABench : state.teamBBench);
  court.remove(outId);
  if (!bench.contains(outId)) bench.add(outId);
  bench.remove(inId);
  if (!court.contains(inId)) court.add(inId);

  final newLog = List<ScoreEvent>.from(state.scoreLog)
    ..add(ScoreEvent(
      period: period,
      teamId: teamId,
      playerId: outId,    // quién salió
      playerNumber: inId, // quién entró (mismo "hack" que la app en vivo)
      points: 0,
      scoreAfter: 0,
      type: 'SUB',
    ));

  if (teamId == 'A') {
    state = state.copyWith(
      playerStats: newStats,
      teamAOnCourt: court,
      teamABench: bench,
      scoreLog: newLog,
    );
  } else {
    state = state.copyWith(
      playerStats: newStats,
      teamBOnCourt: court,
      teamBBench: bench,
      scoreLog: newLog,
    );
  }
}

  void setObservaciones(String text) {
    state = state.copyWith(observaciones: text);
    _saveToDatabase();
  }

  @override
  Future<bool> finalizeAndSync(
    MatchApi api,
    Uint8List? signatureBytes,
    Uint8List? pdfBytes,
    String teamAName,
    String teamBName,
  ) async {
    String? signatureBase64;
    if (signatureBytes != null) {
      signatureBase64 = base64Encode(signatureBytes);
      await _dao.saveSignature(state.matchId, signatureBase64);
    }

    // Aquí había una copia de la búsqueda de firmas de árbitro: dos consultas
    // a `officials` y dos `base64Decode` cuyos resultados se guardaban en
    // variables marcadas `// ignore: unused_local_variable`. Código muerto que
    // además pegaba a la base de datos en cada cierre de partido.
    //
    // Las firmas las recupera `OfficialRepository.getRefereeSignatures`, que
    // es quien las usa de verdad (para el PDF, desde `MatchFinalizer`).

    String? localPdfPath;
    if (pdfBytes != null) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/match_${state.matchId}.pdf');
        await file.writeAsBytes(pdfBytes);
        localPdfPath = file.path;

        await (_dao.update(
          _dao.db.matches,
        )..where((tbl) => tbl.id.equals(state.matchId))).write(
          MatchesCompanion(matchReportPath: drift.Value(localPdfPath)),
        );
      } catch (e) {
        // Silencio en release
      }
    }

    // --- CORRECCIÓN DE SEGURIDAD: DOBLE VERIFICACIÓN DEL FIXTURE ID ---
    String? finalFixtureId = state.fixtureId;
    
    // Si el estado en RAM no lo tiene, lo buscamos en la BD directamente
    if (finalFixtureId == null || finalFixtureId.isEmpty) {
      final matchFromDb = await (_dao.db.select(_dao.db.matches)
          ..where((m) => m.id.equals(state.matchId)))
          .getSingleOrNull();
      finalFixtureId = matchFromDb?.fixtureId;
    }
    //

    // Fuente COMPLETA de eventos: tabla gameEvents (incluye posesión, tiempos
    // fuera y cambios), no solo state.scoreLog (que trae anotación/faltas).
    final eventRows = await (_dao.db.select(_dao.db.gameEvents).join([
      drift.leftOuterJoin(
        _dao.db.matchRosters,
        _dao.db.matchRosters.matchId.equalsExp(_dao.db.gameEvents.matchId) &
            _dao.db.matchRosters.playerId.equalsExp(_dao.db.gameEvents.playerId),
      ),
      drift.leftOuterJoin(
        _dao.db.players,
        _dao.db.players.id.equalsExp(_dao.db.gameEvents.playerId),
      ),
    ])
          ..where(_dao.db.gameEvents.matchId.equals(state.matchId))
          ..orderBy([drift.OrderingTerm.asc(_dao.db.gameEvents.createdAt)]))
        .get();

    final eventsList = MatchPayloadMapper.mapEvents(
      eventRows.map(
        (row) => (
          event: row.readTable(_dao.db.gameEvents),
          roster: row.readTableOrNull(_dao.db.matchRosters),
          player: row.readTableOrNull(_dao.db.players),
        ),
      ),
    ).map((e) => e.payload).toList();

    final rosterRows = await (_dao.db.select(
      _dao.db.matchRosters,
    )..where((r) => r.matchId.equals(state.matchId))).get();

    final rostersList = rosterRows
        // Los jugadores con id temporal negativo aun no existen en la nube:
        // enviarlos rompe la FK del backend.
        .where((r) => (int.tryParse(r.playerId) ?? 0) > 0)
        .map((r) {
          final forfeited = MatchPayloadMapper.teamForfeited(
            r.teamSide,
            state.forfeitStatus,
          );
          // Al cerrar el partido SI hay estadisticas vivas: se usan en vez de
          // releer los eventos.
          final stats = state.playerStats.values
              .where((p) => p.dbId.toString() == r.playerId)
              .firstOrNull;
          final played =
              !forfeited &&
              stats != null &&
              (stats.isStarter ||
                  stats.isOnCourt ||
                  stats.points > 0 ||
                  stats.fouls > 0);

          return MatchPayloadMapper.mapRoster(
            r,
            playerId: int.tryParse(r.playerId) ?? 0,
            hasPlayed: played,
          );
        })
        .toList();

    final formattedDate = MatchPayloadMapper.backendDateTime(DateTime.now());

    final payload = {
      "match_id": state.matchId,
      "fixture_id": finalFixtureId,
      "tournament_id": state.tournamentId,
      "venue_id": state.venueId,
      "team_a_id": state.teamAId,
      "team_b_id": state.teamBId,
      "team_a_name": teamAName,
      "team_b_name": teamBName,
      "score_a": state.scoreA,
      "score_b": state.scoreB,
      "current_period": state.currentPeriod,
      "time_left": MatchClockFormat.format(state.timeLeft),
      "main_referee": state.mainReferee,
      "aux_referee": state.auxReferee,
      "scorekeeper": state.scorekeeper,
      "forfeit_status": state.forfeitStatus,
      "observaciones": state.observaciones,
      "match_date": formattedDate,
      "signature_base64": signatureBase64,
      "events": eventsList,
      "rosters": rostersList,
    };

    try {
      final success = (await api.syncMatchDataMultipart(
        matchData: payload,
        pdfBytes: pdfBytes,
      )).isOk;
      if (success) {
        await _dao.markAsSynced(state.matchId);
        //if (localPdfPath != null) File(localPdfPath).delete();
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  /// Persiste la asistencia del partido según la regla de dominio:
  /// asistió = jugó (titular/en cancha/anotó/faltó) O marcado manualmente.
  /// Un equipo en forfeit no asiste. Se llama antes de finalizar.
  Future<void> commitAttendance({Set<int> manuallyPresent = const {}}) async {
    final rosters = await _dao.getRostersForMatch(state.matchId);
    final Map<String, bool> attendanceByPlayer = {};

    for (final r in rosters) {
      final pid = int.tryParse(r.playerId) ?? 0;

      final bool teamForfeited =
          (r.teamSide == 'A' && (state.forfeitStatus == ForfeitStatus.teamA || state.forfeitStatus == ForfeitStatus.both)) ||
          (r.teamSide == 'B' && (state.forfeitStatus == ForfeitStatus.teamB || state.forfeitStatus == ForfeitStatus.both));

      bool played = false;
      if (!teamForfeited) {
        final ps = state.playerStats.values.where((p) => p.dbId == pid).firstOrNull;
        played = ps != null && (ps.isStarter || ps.isOnCourt || ps.points > 0 || ps.fouls > 0);
      }

      final bool attended = !teamForfeited && (played || manuallyPresent.contains(pid));
      attendanceByPlayer[r.playerId] = attended;
    }

    await _dao.setAttendanceBatch(state.matchId, attendanceByPlayer);
  }

  /// Jugadores pendientes de asistencia, agrupados por equipo ('A' / 'B').
  /// Excluye a los que ya jugaron (asistencia automática) y a los del equipo
  /// en forfeit. Un mapa vacío significa que no hay a quién preguntar.
  Map<String, List<PlayerStats>> playersPendingAttendanceByTeam({String? forfeitOverride}) {
    final ef = forfeitOverride ?? state.forfeitStatus;
    final forfeitA = ef == 'A' || ef == 'BOTH' || ef == ForfeitStatus.teamA || ef == ForfeitStatus.both;
    final forfeitB = ef == 'B' || ef == 'BOTH' || ef == ForfeitStatus.teamB || ef == ForfeitStatus.both;

    if (forfeitA && forfeitB) return {};

    final Map<String, List<PlayerStats>> result = {'A': [], 'B': []};

    state.playerStats.forEach((key, ps) {
      if (ps.isStarter || ps.isOnCourt || ps.points > 0 || ps.fouls > 0) return;
      final side = state.teamAOnCourt.contains(key) || state.teamABench.contains(key) ? 'A' : 'B';
      if (side == 'A' && forfeitA) return;
      if (side == 'B' && forfeitB) return;
      result[side]!.add(ps);
    });

    // Limpia lados vacíos para simplificar el consumidor.
    result.removeWhere((_, list) => list.isEmpty);
    return result;
  }

  // función para el Default
  void declareForfeit(String defaultingTeam) {
    // defaultingTeam puede ser 'A', 'B' o 'BOTH'
    int newScoreA = 0;
    int newScoreB = 0;

    if (defaultingTeam == 'A') {
      newScoreB = 20; // Pierde A por default 0-20
    } else if (defaultingTeam == 'B') {
      newScoreA = 20; // Pierde B por default 20-0
    }

    state = state.copyWith(
      scoreA: newScoreA,
      scoreB: newScoreB,
      forfeitStatus: defaultingTeam == 'A'
          ? 'TEAM_A'
          : (defaultingTeam == 'B' ? 'TEAM_B' : 'BOTH'),
      timeLeft: const Duration(seconds: 0),
    );

    _pause();
    _saveToDatabase();
  }

  /// Cambia el desenlace de un partido ya finalizado. Aplica la regla de
  /// marcador según el tipo y NO toca eventos ni rosters.
  /// tipo: 'NONE' (normal), 'TEAM_A', 'TEAM_B', 'BOTH' (forfeit), 'PROTEST'.
  ///
  /// [api] necesario SOLO para el caso NONE sin eventos locales (forfeit→normal):
  /// recalcula el marcador real desde score_logs en el backend (online-only).
  @override
  Future<MatchState> changeOutcome(
    String tipo,
    MatchApi api, {
    Uint8List? signature,
    String? observaciones,
  }) async {
    if (tipo == 'TEAM_A' || tipo == 'TEAM_B' || tipo == 'BOTH') {
      declareForfeit(tipo == 'TEAM_A' ? 'A' : (tipo == 'TEAM_B' ? 'B' : 'BOTH'));
    } else {
      int a = 0, b = 0;

      if (state.scoreLog.isNotEmpty) {
        // Hay eventos locales: el marcador real se recalcula sin red.
        for (final e in state.scoreLog) {
          if (e.teamId == 'A') a += e.points;
          if (e.teamId == 'B') b += e.points;
        }
      } else {
        // forfeit→normal sin eventos locales (la descarga los borró):
        // el marcador real vive en score_logs del backend. Online-only.
        // Online-only: sin eventos locales el marcador real solo existe en
        // score_logs del backend. Se relanza la AppException tipada para que
        // la pantalla la capture y muestre su mensaje.
        final real = switch (await api.getRealScores(state.matchId)) {
          Ok(:final value) => value,
          Err(:final error) => throw error,
        };
        a = real.scoreA;
        b = real.scoreB;
      }

      state = state.copyWith(scoreA: a, scoreB: b, forfeitStatus: 'NONE');
    }
    if (observaciones != null) setObservaciones(observaciones);
    unawaited(_saveToDatabase());
    return state; // ← el orquestador usa este retorno, no accede a state directo
  }

  /// Concede un tiempo muerto al equipo si le queda cupo.
  ///
  /// Las REGLAS (cuantos por tramo, la quema del clutch time, el minuto que
  /// se anota en el acta) viven en TimeoutEngine, que es puro y esta cubierto
  /// por tests.
  void addTimeout(String teamId) {
    final granted = TimeoutEngine.grant(state, teamId);
    // Cupo agotado: no se registra ni se mete en el historial de deshacer.
    if (granted == null) return;

    _saveToHistory();
    state = granted;
    _logEventToDb(null, 0, 0, EventType.timeoutFor(teamId));
  }

  void addTeamFoul(String teamId, String type) {
    _saveToHistory();
    String specialName = type == 'C' ? "Entrenador" : "Banca";

    List<ScoreEvent> newScoreLog = List.from(state.scoreLog);
    newScoreLog.add(
      ScoreEvent(
        period: state.currentPeriod,
        teamId: teamId,
        playerId: specialName,
        dbPlayerId: 0,
        playerNumber: "",
        points: 0,
        scoreAfter: (teamId == 'A' ? state.scoreA : state.scoreB),
        type: type,
      ),
    );

    state = state.copyWith(scoreLog: newScoreLog);
    _saveToDatabase();
    _logEventToDb(null, 0, 1, '${type}_$teamId');
  }





  void _start() {
    state = state.copyWith(isRunning: true);
    _clock.start(_onTick);
  }

  /// Un segundo de reloj. Las REGLAS (cuando quemar tiempos muertos, cada
  /// cuanto persistir, cuando se acabo) viven en GameClockRules, que es puro
  /// y esta cubierto por tests; aqui solo quedan los efectos.
  void _onTick() {
    final tick = GameClockRules.advance(state);

    if (tick.expired) {
      _pause();
      _saveToDatabase();
      return;
    }

    state = state.copyWith(timeLeft: tick.timeLeft);
    if (tick.shouldAutoBurn) _applyAutoBurn();
    if (tick.shouldPersist) _saveToDatabase();
  }

  // IDs de jugadores marcados presentes manualmente (asistieron sin jugar).
  final Set<int> _manualAttendance = {};

  void setManualAttendance(int playerDbId, bool present) {
    if (present) {
      _manualAttendance.add(playerDbId);
    } else {
      _manualAttendance.remove(playerDbId);
    }
  }

  bool didAttend(int playerDbId, {required bool played}) {
    return played || _manualAttendance.contains(playerDbId);
  }

  /// Quema los tiempos muertos de la segunda mitad que no se hayan usado al
  /// llegar al "clutch time".
  void _applyAutoBurn() {
    final burned = GameClockRules.applyAutoBurn(state);
    // `null` significa que no habia nada que quemar: no se ensucia el
    // historial de deshacer con un paso que no cambio nada.
    if (burned == null) return;

    _saveToHistory();
    state = burned;
    _saveToDatabase();
  }

  void initializeNewMatch({
    required String matchId,
    String? fixtureId,
    required List<CatalogPlayer> rosterA,
    required List<CatalogPlayer> rosterB,
    required Set<int> startersA,
    required Set<int> startersB,
    required int tournamentId,
    required int venueId,
    required int teamAId,
    required int teamBId,
    required String mainReferee,
    required String auxReferee,
    required String scorekeeper,
  }) {
    // Un partido nuevo arranca con el reloj parado.
    _clock.stop();
    _dao.updateMatchMetadata(
      matchId,
      fixtureId,
      teamAId,
      teamBId,
      mainReferee,
      auxReferee,
      scorekeeper,
      markInProgress: !_isFinished,
    );
    final Map<String, PlayerStats> initialStats = {};
    final List<String> courtA = [];
    final List<String> benchA = [];
    final List<String> courtB = [];
    final List<String> benchB = [];

    // Para equipo A
    for (var player in rosterA) {
      final isStarter = startersA.contains(player.id);
      // USAMOS player.id.toString() como LLAVE en lugar de player.name
      initialStats[player.id.toString()] = PlayerStats(
        dbId: player.id,
        playerName: player.name,
        isOnCourt: isStarter,
        isStarter: isStarter,
        hasPlayed: isStarter,
        playerNumber: player.defaultNumber.toString(),
      );
      if (isStarter) {
        courtA.add(player.id.toString()); // Guardamos ID, no nombre
      } else {
        benchA.add(player.id.toString());
      }
    }

    for (var player in rosterB) {
      final isStarter = startersB.contains(player.id);
      initialStats[player.id.toString()] = PlayerStats(
        dbId: player.id,
        playerName: player.name,
        isOnCourt: isStarter,
        isStarter: isStarter,
        hasPlayed: isStarter,
        playerNumber: player.defaultNumber.toString(),
      );
      if (isStarter) {
        courtB.add(player.id.toString());
      } else {
        benchB.add(player.id.toString());
      }
    }

    state = state.copyWith(
      matchId: matchId,
      fixtureId: fixtureId,
      playerStats: initialStats,
      teamAOnCourt: courtA,
      teamABench: benchA,
      teamBOnCourt: courtB,
      teamBBench: benchB,
      scoreA: 0,
      scoreB: 0,
      currentPeriod: 1,
      possession: '',
      timeLeft: const Duration(minutes: 10),
      scoreLog: [],
      periodScores: {
        1: [0, 0],
      },
      tournamentId: tournamentId,
      venueId: venueId,
      teamAId: teamAId,
      teamBId: teamBId,
      mainReferee: mainReferee,
      auxReferee: auxReferee,
      scorekeeper: scorekeeper,
      teamATimeouts1: [],
      teamATimeouts2: [],
      teamAOTTimeouts: [],
      teamBTimeouts1: [],
      teamBTimeouts2: [],
      teamBOTTimeouts: [],
      forfeitStatus: 'NONE',         
      observaciones: '',
    );
  }

  void setPossession(String team) {
    _saveToHistory();
    final String newPossession = (state.possession == team) ? '' : team;
    state = state.copyWith(possession: newPossession);
    // Persistimos la posesión como evento, para poder restaurarla al reanudar.
    _logEventToDb(null, 0, 0, newPossession.isEmpty ? EventType.possNone : EventType.possessionFor(newPossession));
  }

  void initMatch(String matchId) {}

  void _saveToHistory() => _history.push(state);

  void undo() {
    final previous = _history.pop();
    if (previous == null) return;

    // El reloj NO se deshace: el tiempo sigue corriendo mientras el anotador
    // corrige, y devolverlo atras falsearia el acta.
    state = previous.copyWith(
      timeLeft: state.timeLeft,
      isRunning: state.isRunning,
    );
    _saveToDatabase();
  }

  void setTime(Duration newTime) {
    state = state.copyWith(timeLeft: newTime);
  }

  void adjustTime(int seconds) {
    final newSeconds = state.timeLeft.inSeconds + seconds;
    if (newSeconds < 0) return;
    state = state.copyWith(timeLeft: Duration(seconds: newSeconds));
  }

  void nextPeriod() {
    _saveToHistory();
    int nextPeriodIdx = state.currentPeriod + 1;
    Duration newDuration = (nextPeriodIdx > 4)
        ? const Duration(minutes: 5)
        : const Duration(minutes: 10);

    final newPeriodScores = Map<int, List<int>>.from(state.periodScores);
    if (!newPeriodScores.containsKey(nextPeriodIdx)) {
      newPeriodScores[nextPeriodIdx] = [0, 0];
    }

    state = state.copyWith(
      currentPeriod: nextPeriodIdx,
      timeLeft: newDuration,
      isRunning: false,
      periodScores: newPeriodScores,
    );
    _saveToDatabase();
  }

  void setPeriod(int period) {
    _saveToHistory();
    Duration newDuration = (period > 4)
        ? const Duration(minutes: 5)
        : const Duration(minutes: 10);

    final newPeriodScores = Map<int, List<int>>.from(state.periodScores);
    if (!newPeriodScores.containsKey(period)) newPeriodScores[period] = [0, 0];

    state = state.copyWith(
      currentPeriod: period,
      timeLeft: newDuration,
      isRunning: false,
      periodScores: newPeriodScores,
    );
    _saveToDatabase();
  }

  void toggleTimer() {
    if (state.isRunning) {
      _pause();
    } else {
      _start();
    }
  }

  /// Detiene el reloj y marca el partido como finalizado, para que los
  /// guardados posteriores no reviertan el estado a IN_PROGRESS.
  void markAsFinished() {
    _clock.stop();
    _isFinished = true;
    state = state.copyWith(isRunning: false);
  }

  void _pause() {
    _clock.stop();
    state = state.copyWith(isRunning: false);
    _saveToDatabase();
  }

  /// Registra puntos o una falta de un jugador.
  ///
  /// Las REGLAS (pertenencia al equipo, limite de 5 faltas, marcador por
  /// periodo, log de eventos) viven en `ScoreEngine`, que es una funcion pura
  /// y esta cubierta por tests. Aqui solo queda lo que el motor no puede
  /// hacer: guardar el historial de deshacer y persistir.
  void updateStats(
    String teamId,
    String playerId, {
    int points = 0,
    int fouls = 0,
    String? foulType,
  }) {
    final outcome = ScoreEngine.applyPlayerAction(
      state,
      teamId: teamId,
      playerId: playerId,
      points: points,
      fouls: fouls,
      foulType: foulType,
    );

    // Una accion rechazada no debe ensuciar el historial ni la base de datos.
    if (outcome is! ScoreApplied) return;

    _saveToHistory();
    state = outcome.state;

    _saveToDatabase();
    if (outcome.event != null) {
      _logEventToDb(outcome.event!.dbPlayerId.toString(), points, fouls, foulType);
    }
  }

  /// Cambio de jugador.
  ///
  /// Las reglas viven en SubstitutionEngine, que ademas VALIDA que el que sale
  /// este en cancha y el que entra en banca. Antes se aplicaba a ciegas: un
  /// doble toque podia dejar seis jugadores en cancha o duplicar a uno.
  void substitutePlayer(String teamId, String playerOutId, String playerInId) {
    final result = SubstitutionEngine.substitute(
      state,
      teamId: teamId,
      playerOutId: playerOutId,
      playerInId: playerInId,
    );
    if (result == null) return;

    _saveToHistory();
    state = result;

    _saveToDatabase();
    _logEventToDb(
      null,
      0,
      0,
      EventType.subEvent(side: teamId, outId: playerOutId, inId: playerInId),
    );
  }

  // --- LÓGICA DE UNDO SELECTIVO ---


// Añade el undo de Tiempo Fuera (Opcional pero recomendado)
void undoLastTimeout() {
  final undone = TimeoutUndo.undoLast(state);
  if (undone == null) return;

  _saveToHistory();
  state = undone;
  _saveToDatabase();
}

void undoLastPoint() {
  final lastPoint = state.scoreLog.where((e) => e.points > 0).lastOrNull;
  if (lastPoint == null) return;
  _saveToHistory();

  final currentStats = state.playerStats[lastPoint.playerId]!;
  
  // 1. Revertir puntos del jugador
  final newStats = currentStats.copyWith(
    points: currentStats.points - lastPoint.points,
  );

  // 2. Revertir marcador global y de periodo
  final newPeriodScores = Map<int, List<int>>.from(state.periodScores);
  newPeriodScores[lastPoint.period]![lastPoint.teamId == 'A' ? 0 : 1] -= lastPoint.points;

  state = state.copyWith(
    scoreA: lastPoint.teamId == 'A' ? state.scoreA - lastPoint.points : state.scoreA,
    scoreB: lastPoint.teamId == 'B' ? state.scoreB - lastPoint.points : state.scoreB,
    playerStats: {...state.playerStats, lastPoint.playerId: newStats},
    scoreLog: state.scoreLog.where((e) => e != lastPoint).toList(), // Eliminar del log
    periodScores: newPeriodScores,
  );
  _saveToDatabase();
}

void undoLastFoul() {
  final lastFoul = state.scoreLog.where((e) => EventType.isPlayerFoul(e.type)).lastOrNull;
  if (lastFoul == null) return;
  _saveToHistory();

  final currentStats = state.playerStats[lastFoul.playerId]!;
  List<String> newFoulDetails = List.from(currentStats.foulDetails)..remove(lastFoul.type);

  state = state.copyWith(
    playerStats: {
      ...state.playerStats,
      lastFoul.playerId: currentStats.copyWith(
        fouls: currentStats.fouls - 1,
        foulDetails: newFoulDetails,
      )
    },
    scoreLog: state.scoreLog.where((e) => e != lastFoul).toList(),
  );
  _saveToDatabase();
}

void undoLastSubstitution() {
  final lastSub = state.scoreLog.where((e) => e.type == 'SUB').lastOrNull;
  if (lastSub == null) return;

  // El truco aquí es simplemente llamar a substitutePlayer pero al revés
  // lastSub.playerId es el que salió, lastSub.playerNumber es el que entró
  substitutePlayer(lastSub.teamId, lastSub.playerNumber, lastSub.playerId);
  
  // Limpiamos los dos eventos de sustitución (el original y el de reversión) del log
  // para que no ensucien el acta PDF final
  state = state.copyWith(
    scoreLog: state.scoreLog.where((e) => !EventType.isSub(e.type)).toList()
  );
}

  Future<void> _saveToDatabase() async {
    if (state.matchId.isEmpty) return;
    // Si el partido ya finalizó, no seguimos escribiendo IN_PROGRESS:
    // eso revertiría el estado FINISHED que dejó el finalizador.
    if (_isFinished) return;
    final timeStr = MatchClockFormat.format(state.timeLeft);
    await _dao.updateMatchStatus(
      state.matchId,
      state.scoreA,
      state.scoreB,
      timeStr,
      MatchStatus.inProgress,
      forfeitStatus: state.forfeitStatus,
      observaciones: state.observaciones,
      currentPeriod: state.currentPeriod,
    );
  }

  Future<void> _logEventToDb(
    String? playeridDb,
    int points,
    int fouls,
    String? customType,
  ) async {
    if (state.matchId.isEmpty) return;
    String type = "UNKNOWN";
    if (points == 1) {
      type = "POINT_1";
    } else if (points == 2) {
      type = "POINT_2";
    } else if (points == 3) {
      type = "POINT_3";
    } else if (customType != null) {
      type = customType;
    } else if (fouls > 0) {
      type = "FOUL";
    }

    final timeStr = MatchClockFormat.format(state.timeLeft);

    await _dao.insertEvent(
      GameEventsCompanion.insert(
        matchId: state.matchId,
        playerId: drift.Value(playeridDb),
        type: type,
        period: state.currentPeriod,
        clockTime: timeStr,
        isSynced: const drift.Value(false),
      ),
    );
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void updateMatchPlayerInfo(String playerId, {String? newNumber}) {
    if (!state.playerStats.containsKey(playerId)) return;
    final currentStats = state.playerStats[playerId]!;
    final newStats = currentStats.copyWith(
      playerNumber: newNumber ?? currentStats.playerNumber,
    );
    final newPlayerStatsMap = Map<String, PlayerStats>.from(state.playerStats);
    newPlayerStatsMap[playerId] = newStats;
    state = state.copyWith(playerStats: newPlayerStatsMap);
  }


  // =========================================================================
  // --- AÑADIR JUGADOR MID-GAME (SOPORTE OFFLINE-FIRST) ---
  // =========================================================================
  
  Future<void> addNewPlayerToMatch({
    required String teamSide,
    required String name,
    required int number,
    required TeamApi api,
  }) async {
    final teamId = teamSide == 'A' ? state.teamAId : state.teamBId;
    if (teamId == null) {
      throw Exception("Error crítico: ID del equipo no encontrado en el partido.");
    }

    final isNumberTaken = state.playerStats.values.any((p) {
      final belongsToTeam = teamSide == 'A'
          ? (state.teamAOnCourt.contains(p.dbId.toString()) || state.teamABench.contains(p.dbId.toString()))
          : (state.teamBOnCourt.contains(p.dbId.toString()) || state.teamBBench.contains(p.dbId.toString()));
          
      return belongsToTeam && p.playerNumber == number.toString();
    });

    if (isNumberTaken) {
      throw Exception("El número $number ya está en uso en este equipo.");
    }

    int newPlayerId;
    bool isOnlineSync = false;

    // 3. ESTRATEGIA DE ID NEGATIVO
    try {
      // Intentamos subirlo a la nube
      newPlayerId = switch (await api.addPlayer(teamId, name, number)) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      };
      isOnlineSync = true;
    } catch (e) {
      // Si falla (no hay internet), creamos un ID negativo único local basado en el tiempo
      // Esto garantiza matemáticamente que nunca chocará con un ID de la nube.
      newPlayerId = TempId.nextNegative();
      isOnlineSync = false;
    }

    final String playerKey = newPlayerId.toString();

    // 4. Persistencia Local (DAO)
    await _dao.saveMidGamePlayerLocally(
      matchId: state.matchId,
      playerId: newPlayerId,
      teamId: teamId,
      name: name,
      number: number,
      teamSide: teamSide,
      isSynced: isOnlineSync, // Le decimos a SQLite si ya está en la nube o no
    );

    // 5. Actualización RAM
    final freshStatsMap = Map<String, PlayerStats>.from(state.playerStats);
    freshStatsMap[playerKey] = PlayerStats(
      dbId: newPlayerId,
      playerName: name,
      playerNumber: number.toString(),
      isOnCourt: false,
      isStarter: false,
      hasPlayed: false,
    );

    List<String> freshBenchA = List.from(state.teamABench);
    List<String> freshBenchB = List.from(state.teamBBench);

    if (teamSide == 'A') {
      freshBenchA.add(playerKey);
    } else {
      freshBenchB.add(playerKey);
    }

    state = state.copyWith(
      playerStats: freshStatsMap,
      teamABench: freshBenchA,
      teamBBench: freshBenchB,
    );

    unawaited(_saveToDatabase());
  }

  // =========================================================================
  // --- RECONCILIACIÓN PRE-SYNC ---
  // =========================================================================

  /// Busca jugadores creados offline (ID negativo) y los sube a la nube.
  /// Luego intercambia el ID viejo por el nuevo en SQLite y en la RAM.
  /// Desenvuelve el id de un jugador recien subido o relanza el error.
  /// El llamador ya envuelve la reconciliacion en un `try/catch`.
  static int _unwrapPlayerId(Result<int> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };

  @override
  Future<void> reconcileOfflinePlayers(TeamApi api) async {
    // Extraemos solo los jugadores que tienen un ID negativo
    final offlinePlayers = state.playerStats.values.where((p) => p.dbId < 0).toList();
    
    if (offlinePlayers.isEmpty) return; // No hay nada que reconciliar

    Map<String, PlayerStats> newStatsMap = Map.from(state.playerStats);
    List<String> newBenchA = List.from(state.teamABench);
    List<String> newCourtA = List.from(state.teamAOnCourt);
    List<String> newBenchB = List.from(state.teamBBench);
    List<String> newCourtB = List.from(state.teamBOnCourt);
    List<ScoreEvent> newScoreLog = List.from(state.scoreLog);

    for (var offlinePlayer in offlinePlayers) {
      final oldIdStr = offlinePlayer.dbId.toString();
      final teamIdInt = (newCourtA.contains(oldIdStr) || newBenchA.contains(oldIdStr)) ? state.teamAId : state.teamBId;
      
      if (teamIdInt == null) continue;

      try {
        // 1. Subir a la nube
        final realId = _unwrapPlayerId(await api.addPlayer(teamIdInt, offlinePlayer.playerName, int.parse(offlinePlayer.playerNumber)));
        final realIdStr = realId.toString();

        // 2. Reconciliar SQLite (Capa de Datos)
        await _dao.replaceTempPlayerId(oldIdStr, realIdStr);

        // 3. Reconciliar Estadísticas en RAM
        final statsObj = newStatsMap.remove(oldIdStr);
        if (statsObj != null) {
          newStatsMap[realIdStr] = statsObj.copyWith(dbId: realId);
        }

        // 4. Reconciliar Rosters en RAM
        _replaceInList(newBenchA, oldIdStr, realIdStr);
        _replaceInList(newCourtA, oldIdStr, realIdStr);
        _replaceInList(newBenchB, oldIdStr, realIdStr);
        _replaceInList(newCourtB, oldIdStr, realIdStr);

        // 5. Reconciliar Historial (ScoreLog)
        for (int i = 0; i < newScoreLog.length; i++) {
          final ev = newScoreLog[i];
          if (ev.playerId == oldIdStr) {
            newScoreLog[i] = ScoreEvent(
              period: ev.period,
              teamId: ev.teamId,
              playerId: realIdStr, // <--- Actualizamos al ID nuevo
              dbPlayerId: realId,  
              playerNumber: ev.playerNumber,
              points: ev.points,
              scoreAfter: ev.scoreAfter,
              type: ev.type,
            );
          }
        }
      } catch (e) {
        throw Exception("Fallo al sincronizar jugador offline '${offlinePlayer.playerName}'. Requiere internet.");
      }
    }

    // 6. Emitimos el estado corregido
    state = state.copyWith(
      playerStats: newStatsMap,
      teamABench: newBenchA,
      teamAOnCourt: newCourtA,
      teamBBench: newBenchB,
      teamBOnCourt: newCourtB,
      scoreLog: newScoreLog,
    );
  }

  // Helper privado para cambiar IDs en listas
  void _replaceInList(List<String> list, String oldItem, String newItem) {
    final index = list.indexOf(oldItem);
    if (index != -1) {
      list[index] = newItem;
    }
  }

}

final matchGameProvider =
    StateNotifierProvider<MatchGameController, MatchState>((ref) {
      final dao = ref.watch(matchesDaoProvider);
      return MatchGameController(dao);
    });
