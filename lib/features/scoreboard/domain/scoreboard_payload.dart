import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';

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
        'state': state.toJson(),
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
        state: MatchState.fromJson(
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
      state: MatchState.fromJson(json),
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
