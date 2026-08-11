import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';

/// Serialización del estado del partido **para el cable del marcador**.
///
/// Vivía como `MatchState.toJson()`/`fromJson()` dentro del archivo del
/// controller. Estaba en el sitio equivocado por dos motivos:
///
/// 1. Obligaba a `scoreboard/domain` a importar `match/presentation`, es decir
///    la regla de dependencia al revés.
/// 2. Un `toJson` en la entidad da a entender que serializa la entidad. No lo
///    hace: emite **14 de sus 30 campos**, los que la TV necesita para pintar.
///    Quien añadiera un campo a `MatchState` esperaría verlo viajar, y no
///    viajaría. Ahora el recorte es explícito y vive donde se decide.
///
/// **Lo que NO viaja, y por qué:** `scoreLog` y `playerStats` son las listas
/// más grandes del estado y el receptor no las usa — las faltas de equipo se
/// calculan en el emisor (`teamAFouls`) y se mandan ya resueltas. Enviarlas
/// multiplicaría el tamaño de cada mensaje, que se emite con cada tick.
extension ScoreboardWire on MatchState {
  /// **Las claves son el contrato con los receptores** (invariante I4 del
  /// plan). Una TV con la build anterior debe seguir decodificando esto, así
  /// que solo se pueden AÑADIR claves, nunca renombrar ni quitar.
  Map<String, dynamic> toScoreboardJson() => {
    'scoreA': scoreA,
    'scoreB': scoreB,
    // En segundos: `Duration` no es serializable a JSON.
    'timeLeft': timeLeft.inSeconds,
    'isRunning': isRunning,
    'currentPeriod': currentPeriod,
    'possession': possession,
    'teamATimeouts1': teamATimeouts1,
    'teamATimeouts2': teamATimeouts2,
    'teamAOTTimeouts': teamAOTTimeouts,
    'teamBTimeouts1': teamBTimeouts1,
    'teamBTimeouts2': teamBTimeouts2,
    'teamBOTTimeouts': teamBOTTimeouts,
    'forfeitStatus': forfeitStatus,
    'observaciones': observaciones,
  };

  /// Reconstruye lo que cabe en el cable. Todo lleva valor por defecto: un
  /// emisor con otra versión puede omitir campos y la TV sigue pintando.
  static MatchState fromScoreboardJson(Map<String, dynamic> json) {
    return MatchState(
      scoreA: json['scoreA'] as int? ?? 0,
      scoreB: json['scoreB'] as int? ?? 0,
      timeLeft: Duration(seconds: json['timeLeft'] as int? ?? 0),
      isRunning: json['isRunning'] as bool? ?? false,
      currentPeriod: json['currentPeriod'] as int? ?? 1,
      possession: json['possession'] as String? ?? '',
      teamATimeouts1: List<String>.from(json['teamATimeouts1'] ?? const []),
      teamATimeouts2: List<String>.from(json['teamATimeouts2'] ?? const []),
      teamAOTTimeouts: List<String>.from(json['teamAOTTimeouts'] ?? const []),
      teamBTimeouts1: List<String>.from(json['teamBTimeouts1'] ?? const []),
      teamBTimeouts2: List<String>.from(json['teamBTimeouts2'] ?? const []),
      teamBOTTimeouts: List<String>.from(json['teamBOTTimeouts'] ?? const []),
      forfeitStatus: json['forfeitStatus'] as String? ?? 'NONE',
      observaciones: json['observaciones'] as String? ?? '',
    );
  }
}

/// Metadatos del partido que [MatchState] no transporta pero el marcador de TV
/// necesita. La pantalla de control solo los escribe; la difusión los lee.
@immutable
class ScoreboardMeta {
  const ScoreboardMeta({
    required this.teamAName,
    required this.teamBName,
    this.matchId,
    this.isFinished = false,
  });

  final String teamAName;
  final String teamBName;
  final String? matchId;
  final bool isFinished;

  ScoreboardMeta copyWith({
    String? teamAName,
    String? teamBName,
    String? matchId,
    bool? isFinished,
  }) {
    return ScoreboardMeta(
      teamAName: teamAName ?? this.teamAName,
      teamBName: teamBName ?? this.teamBName,
      matchId: matchId ?? this.matchId,
      isFinished: isFinished ?? this.isFinished,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScoreboardMeta &&
      other.teamAName == teamAName &&
      other.teamBName == teamBName &&
      other.matchId == matchId &&
      other.isFinished == isFinished;

  @override
  int get hashCode => Object.hash(teamAName, teamBName, matchId, isFinished);
}

/// Contrato de cable entre la mesa de control y las pantallas.
///
/// Antes este mapa se construía a mano en tres archivos distintos (el emisor y
/// los dos receptores), así que cualquier campo nuevo obligaba a tocar los tres
/// y era fácil que se desincronizaran.
@immutable
class ScoreboardPayload {
  const ScoreboardPayload({
    required this.state,
    required this.teamAName,
    required this.teamBName,
    required this.teamAFouls,
    required this.teamBFouls,
    this.isFinished = false,
  });

  static const int schemaVersion = 1;

  final MatchState state;
  final String teamAName;
  final String teamBName;
  final int teamAFouls;
  final int teamBFouls;
  final bool isFinished;

  /// Construye el payload a partir del estado del partido y sus metadatos,
  /// calculando las faltas de equipo con la función pura del dominio.
  factory ScoreboardPayload.fromMatch(MatchState state, ScoreboardMeta meta) {
    return ScoreboardPayload(
      state: state,
      teamAName: meta.teamAName,
      teamBName: meta.teamBName,
      teamAFouls: teamFoulsOf(state, 'A'),
      teamBFouls: teamFoulsOf(state, 'B'),
      isFinished: meta.isFinished,
    );
  }

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'state': state.toScoreboardJson(),
    'teamAName': teamAName,
    'teamBName': teamBName,
    'teamAFouls': teamAFouls,
    'teamBFouls': teamBFouls,
    'isFinished': isFinished,
  };

  String encode() => jsonEncode(toJson());

  /// Acepta la forma actual (`{state: {...}, teamAName: ...}`) y la antigua
  /// (mapa plano con solo el `MatchState`), para que emisor y receptor puedan
  /// actualizarse en momentos distintos sin dejar la TV en blanco.
  factory ScoreboardPayload.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('state')) {
      final rawState = json['state'];
      return ScoreboardPayload(
        state: ScoreboardWire.fromScoreboardJson(
          rawState is Map<String, dynamic> ? rawState : const {},
        ),
        teamAName: json['teamAName'] as String? ?? 'Equipo A',
        teamBName: json['teamBName'] as String? ?? 'Equipo B',
        teamAFouls: json['teamAFouls'] as int? ?? 0,
        teamBFouls: json['teamBFouls'] as int? ?? 0,
        isFinished: json['isFinished'] as bool? ?? false,
      );
    }

    // Forma legacy: el mapa ES el MatchState.
    return ScoreboardPayload(
      state: ScoreboardWire.fromScoreboardJson(json),
      teamAName: 'Equipo A',
      teamBName: 'Equipo B',
      teamAFouls: 0,
      teamBFouls: 0,
    );
  }

  /// Decodifica sin lanzar: devuelve `null` si el mensaje no es un payload
  /// válido. Necesario porque cualquiera puede escribir en el socket abierto.
  static ScoreboardPayload? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ScoreboardPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
