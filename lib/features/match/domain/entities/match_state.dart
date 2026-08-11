/// Estado de un partido en curso.
///
/// Vivia dentro de `match_game_controller.dart`, un archivo de
/// **presentacion**. Eso obligaba a `features/scoreboard/domain/` a importar
/// presentacion para poder difundir el marcador: la regla 3 del plan
/// (`domain` no depende de capas superiores) al reves.
///
/// Aqui NO hay serializacion a proposito. El `toJson`/`fromJson` que tenia
/// describia el subconjunto de campos que viaja a la TV, es decir el contrato
/// de la feature de marcador, no de la entidad. Vive en
/// `scoreboard/domain/scoreboard_payload.dart`, que es su dueno. Asi, anadir
/// un campo aqui no cambia en silencio lo que se emite por el WebSocket.
library;

import 'package:myapp/features/match/domain/constants/match_constants.dart';

/// Igualdad elemento a elemento.
///
/// Se escribe aqui en vez de usar `listEquals` de `flutter/foundation`: el
/// dominio no debe depender de Flutter (regla 3 del plan), y anadir el paquete
/// `collection` entero por cuatro lineas no compensa.
bool _sameList<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class ScoreEvent {
  final int period;
  final String teamId;
  final String playerId;
  final int dbPlayerId;
  final String playerNumber;
  final int points;
  final int scoreAfter;
  final String type;

  const ScoreEvent({
    required this.period,
    required this.teamId,
    required this.playerId,
    this.dbPlayerId = 0,
    required this.playerNumber,
    required this.points,
    required this.scoreAfter,
    this.type = "POINT",
  });
}

class PlayerStats {
  final int dbId;
  final String playerName;
  final int points;
  final int fouls;
  final bool isOnCourt;
  final bool isStarter;
  final bool hasPlayed;
  final String playerNumber;
  final List<String> foulDetails;

  const PlayerStats({
    this.dbId = 0,
    this.playerName = "",
    this.points = 0,
    this.fouls = 0,
    this.isOnCourt = false,
    this.isStarter = false,
    this.hasPlayed = false,
    this.playerNumber = "00",
    this.foulDetails = const [],
  });

  PlayerStats copyWith({
    int? dbId,
    String? playerName,
    int? points,
    int? fouls,
    bool? isOnCourt,
    bool? isStarter,
    bool? hasPlayed,
    String? playerNumber,
    List<String>? foulDetails,
  }) {
    return PlayerStats(
      dbId: dbId ?? this.dbId,
      playerName: playerName ?? this.playerName,
      points: points ?? this.points,
      fouls: fouls ?? this.fouls,
      isOnCourt: isOnCourt ?? this.isOnCourt,
      isStarter: isStarter ?? this.isStarter,
      hasPlayed: hasPlayed ?? this.hasPlayed,
      playerNumber: playerNumber ?? this.playerNumber,
      foulDetails: foulDetails ?? this.foulDetails,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerStats &&
      other.dbId == dbId &&
      other.playerName == playerName &&
      other.points == points &&
      other.fouls == fouls &&
      other.isOnCourt == isOnCourt &&
      other.isStarter == isStarter &&
      other.hasPlayed == hasPlayed &&
      other.playerNumber == playerNumber &&
      _sameList(other.foulDetails, foulDetails);

  @override
  int get hashCode => Object.hash(
    dbId,
    playerName,
    points,
    fouls,
    isOnCourt,
    isStarter,
    hasPlayed,
    playerNumber,
    Object.hashAll(foulDetails),
  );
}

class MatchState {
  final String matchId;
  final String? fixtureId;
  final int scoreA;
  final int scoreB;
  final Duration timeLeft;
  final bool isRunning;
  final int currentPeriod;
  final String possession;
  final Map<int, List<int>> periodScores;
  final List<ScoreEvent> scoreLog;
  final int? tournamentId;
  final int? venueId;
  final int? teamAId;
  final int? teamBId;
  final String mainReferee;
  final String auxReferee;
  final String scorekeeper;
  final String forfeitStatus;
  final String observaciones;

  final List<String> teamAOnCourt;
  final List<String> teamABench;
  final List<String> teamBOnCourt;
  final List<String> teamBBench;

  final List<String> teamATimeouts1;
  final List<String> teamATimeouts2;
  final List<String> teamAOTTimeouts;

  final List<String> teamBTimeouts1;
  final List<String> teamBTimeouts2;
  final List<String> teamBOTTimeouts;

  final Map<String, PlayerStats> playerStats;

  const MatchState({
    this.matchId = '',
    this.fixtureId,
    this.scoreA = 0,
    this.scoreB = 0,
    this.timeLeft = const Duration(minutes: 10),
    this.isRunning = false,
    this.currentPeriod = 1,
    this.possession = '',
    this.periodScores = const {
      1: [0, 0],
    },
    this.scoreLog = const [],
    this.teamAOnCourt = const [],
    this.teamABench = const [],
    this.teamBOnCourt = const [],
    this.teamBBench = const [],
    this.playerStats = const {},
    this.tournamentId,
    this.venueId,
    this.teamAId,
    this.teamBId,
    this.mainReferee = '',
    this.auxReferee = '',
    this.scorekeeper = '',
    this.forfeitStatus = 'NONE',
    this.observaciones = '',
    this.teamATimeouts1 = const [],
    this.teamATimeouts2 = const [],
    this.teamAOTTimeouts = const [],
    this.teamBTimeouts1 = const [],
    this.teamBTimeouts2 = const [],
    this.teamBOTTimeouts = const [],
  });

  MatchState copyWith({
    String? matchId,
    String? fixtureId,
    int? scoreA,
    int? scoreB,
    Duration? timeLeft,
    bool? isRunning,
    int? currentPeriod,
    String? possession,
    Map<int, List<int>>? periodScores,
    List<ScoreEvent>? scoreLog,
    List<String>? teamAOnCourt,
    List<String>? teamABench,
    List<String>? teamBOnCourt,
    List<String>? teamBBench,
    Map<String, PlayerStats>? playerStats,
    int? tournamentId,
    int? venueId,
    int? teamAId,
    int? teamBId,
    String? mainReferee,
    String? auxReferee,
    String? scorekeeper,
    String? forfeitStatus,
    String? observaciones,
    List<String>? teamATimeouts1,
    List<String>? teamATimeouts2,
    List<String>? teamAOTTimeouts,
    List<String>? teamBTimeouts1,
    List<String>? teamBTimeouts2,
    List<String>? teamBOTTimeouts,
  }) {
    return MatchState(
      matchId: matchId ?? this.matchId,
      fixtureId: fixtureId ?? this.fixtureId,
      scoreA: scoreA ?? this.scoreA,
      scoreB: scoreB ?? this.scoreB,
      timeLeft: timeLeft ?? this.timeLeft,
      isRunning: isRunning ?? this.isRunning,
      currentPeriod: currentPeriod ?? this.currentPeriod,
      possession: possession ?? this.possession,
      periodScores: periodScores ?? this.periodScores,
      scoreLog: scoreLog ?? this.scoreLog,
      teamAOnCourt: teamAOnCourt ?? this.teamAOnCourt,
      teamABench: teamABench ?? this.teamABench,
      teamBOnCourt: teamBOnCourt ?? this.teamBOnCourt,
      teamBBench: teamBBench ?? this.teamBBench,
      playerStats: playerStats ?? this.playerStats,
      tournamentId: tournamentId ?? this.tournamentId,
      venueId: venueId ?? this.venueId,
      teamAId: teamAId ?? this.teamAId,
      teamBId: teamBId ?? this.teamBId,
      mainReferee: mainReferee ?? this.mainReferee,
      auxReferee: auxReferee ?? this.auxReferee,
      scorekeeper: scorekeeper ?? this.scorekeeper,
      forfeitStatus: forfeitStatus ?? this.forfeitStatus,
      observaciones: observaciones ?? this.observaciones,
      teamATimeouts1: teamATimeouts1 ?? this.teamATimeouts1,
      teamATimeouts2: teamATimeouts2 ?? this.teamATimeouts2,
      teamAOTTimeouts: teamAOTTimeouts ?? this.teamAOTTimeouts,
      teamBTimeouts1: teamBTimeouts1 ?? this.teamBTimeouts1,
      teamBTimeouts2: teamBTimeouts2 ?? this.teamBTimeouts2,
      teamBOTTimeouts: teamBOTTimeouts ?? this.teamBOTTimeouts,
    );
  }
}

/// Faltas de equipo en el periodo en curso.
///
/// Funcion pura sobre [MatchState]: la difusion del marcador la necesita y no
/// debe depender del notifier, que puede estar ya destruido tras un
/// `ref.invalidate(matchGameProvider)`.
int teamFoulsOf(MatchState state, String teamId) {
  return state.scoreLog.where((e) {
    return e.teamId == teamId &&
        e.period == state.currentPeriod &&
        e.points == 0 &&
        EventType.isPlayerFoul(e.type);
  }).length;
}
