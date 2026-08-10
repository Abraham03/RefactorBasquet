import 'package:myapp/core/utils/json_parsing.dart';

/// Un partido del calendario tal como lo devuelve la sincronización de bajada.
///
/// Antes viajaba como `List<dynamic> fixturesRaw` dentro de `CatalogData` y el
/// JSON crudo llegaba hasta la UI: `home_menu_screen._syncData()` hacía
/// `m['team_a'] ?? 'Equipo A'` y `int.tryParse(m['score_a'].toString())` a mano,
/// dentro de una transacción de 160 líneas. Un typo en una clave no fallaba:
/// simplemente guardaba el valor por defecto y nadie se enteraba.
class CatalogFixture {
  final String id;
  final String tournamentId;
  final String roundName;
  final String teamAId;
  final String teamBId;
  final String teamAName;
  final String teamBName;
  final String? logoA;
  final String? logoB;
  final String? venueId;
  final String? venueName;
  final String? matchId;
  final DateTime? scheduledDatetime;
  final int? scoreA;
  final int? scoreB;
  final String status;

  const CatalogFixture({
    required this.id,
    required this.tournamentId,
    required this.roundName,
    required this.teamAId,
    required this.teamBId,
    required this.teamAName,
    required this.teamBName,
    this.logoA,
    this.logoB,
    this.venueId,
    this.venueName,
    this.matchId,
    this.scheduledDatetime,
    this.scoreA,
    this.scoreB,
    this.status = 'SCHEDULED',
  });

  factory CatalogFixture.fromJson(Map<String, dynamic> json) {
    final rawDate = json['scheduled_datetime']?.toString();
    return CatalogFixture(
      id: json['id'].toString(),
      tournamentId: json['tournament_id'].toString(),
      roundName: json['round_name'] as String? ?? 'Jornada',
      teamAId: json['team_a_id'].toString(),
      teamBId: json['team_b_id'].toString(),
      // Los nombres llegan en `team_a`/`team_b`, no en `team_a_name`.
      teamAName: json['team_a'] as String? ?? 'Equipo A',
      teamBName: json['team_b'] as String? ?? 'Equipo B',
      logoA: json['logo_a'] as String?,
      logoB: json['logo_b'] as String?,
      venueId: json['venue_id']?.toString(),
      venueName: json['venue_name'] as String?,
      matchId: json['match_id']?.toString(),
      scheduledDatetime: (rawDate == null || rawDate.isEmpty)
          ? null
          : DateTime.tryParse(rawDate),
      scoreA: parseIntOrNull(json['score_a']),
      scoreB: parseIntOrNull(json['score_b']),
      status: json['status'] as String? ?? 'SCHEDULED',
    );
  }
}

/// Roster de un partido ya finalizado, descargado para poder corregir su
/// asistencia aunque el partido se haya jugado en otro dispositivo.
class CatalogRoster {
  final String matchId;
  final String playerId;
  final String teamSide;
  final int jerseyNumber;
  final bool isCaptain;
  final bool attended;

  const CatalogRoster({
    required this.matchId,
    required this.playerId,
    required this.teamSide,
    required this.jerseyNumber,
    required this.isCaptain,
    required this.attended,
  });

  factory CatalogRoster.fromJson(Map<String, dynamic> json) {
    return CatalogRoster(
      matchId: json['match_id'].toString(),
      playerId: json['player_id'].toString(),
      teamSide: json['team_side']?.toString() ?? 'A',
      jerseyNumber: parseIntOrNull(json['jersey_number']) ?? 0,
      // PHP manda los booleanos como 1/"1"/true.
      isCaptain: parseBool(json['is_captain']),
      attended: parseBool(json['attended']),
    );
  }
}

/// Qué se descargó, para que la pantalla pueda informar sin inspeccionar la BD.
class CatalogDownloadSummary {
  final int tournaments;
  final int teams;
  final int players;
  final int venues;
  final int fixtures;
  final int officials;
  final int finishedRosters;

  const CatalogDownloadSummary({
    required this.tournaments,
    required this.teams,
    required this.players,
    required this.venues,
    required this.fixtures,
    required this.officials,
    required this.finishedRosters,
  });

  int get total =>
      tournaments + teams + players + venues + fixtures + officials;
}
