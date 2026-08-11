import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';

/// Una jugada lista para viajar al backend, junto con lo que el llamador
/// necesita saber de ella.
class MappedEvent {
  /// El payload tal cual lo espera el backend.
  final Map<String, dynamic> payload;

  /// Id del jugador **ya normalizado**: `null` si la jugada no es de nadie
  /// (falta de banca, tiempo fuera).
  final int? playerId;

  /// El jugador tiene id temporal negativo: aún no existe en la nube.
  final bool isOfflinePlayer;

  const MappedEvent({
    required this.payload,
    required this.playerId,
    required this.isOfflinePlayer,
  });
}

/// Traduce las jugadas guardadas a lo que espera `sync_match`.
///
/// **Estaba duplicado byte a byte** entre `SyncRepository` (subida diferida) y
/// `MatchGameController` (cierre del partido). Dos copias de una regla que
/// define el contrato con el backend: cambiar una y olvidar la otra producía
/// actas distintas según por dónde se subieran.
///
/// Es una función pura sobre filas ya leídas: sin red, sin BD, sin estado.
/// El golden de `match_payload_golden_test` fija su salida.
abstract final class MatchPayloadMapper {
  /// Convierte las jugadas conservando el marcador acumulado por equipo.
  ///
  /// El orden de [rows] importa: `score_after` se calcula acumulando, así que
  /// deben venir en el orden en que ocurrieron.
  static List<MappedEvent> mapEvents(
    Iterable<({GameEvent event, RosterEntry? roster, Player? player})> rows,
  ) {
    var runningScoreA = 0;
    var runningScoreB = 0;
    final mapped = <MappedEvent>[];

    for (final row in rows) {
      final event = row.event;

      // El sufijo `_A`/`_B` de las faltas de equipo fija el lado. Se quita
      // para decidir los puntos, pero `type` viaja SIN limpiar: el restore
      // necesita el tipo original íntegro.
      var rawType = event.type;
      var teamSide = row.roster?.teamSide ?? TeamSide.home;
      if (rawType.endsWith('_A')) {
        teamSide = TeamSide.home;
        rawType = rawType.replaceAll('_A', '');
      } else if (rawType.endsWith('_B')) {
        teamSide = TeamSide.away;
        rawType = rawType.replaceAll('_B', '');
      }

      final points = _pointsOf(rawType);
      final isTeamA = teamSide == TeamSide.home;
      if (points > 0) {
        if (isTeamA) {
          runningScoreA += points;
        } else {
          runningScoreB += points;
        }
      }

      final rawPlayerId = event.playerId;
      // '-1' es el centinela de "sin jugador" que usa la UI.
      final parsed =
          (rawPlayerId == null || rawPlayerId.isEmpty || rawPlayerId == '-1')
          ? 0
          : (int.tryParse(rawPlayerId) ?? 0);

      mapped.add(
        MappedEvent(
          playerId: parsed > 0 ? parsed : null,
          isOfflinePlayer: parsed < 0,
          payload: {
            'period': event.period,
            'team_side': teamSide,
            'player_name': row.player?.name ?? '',
            'player_number': row.roster?.jerseyNumber ?? 0,
            'points_scored': points,
            'score_after': isTeamA ? runningScoreA : runningScoreB,
            'type': event.type,
            'clock_time': event.clockTime,
            'player_id': parsed > 0 ? parsed : null,
          },
        ),
      );
    }

    return mapped;
  }

  /// Un jugador del acta, listo para el backend.
  ///
  /// [hasPlayed] se recibe en vez de calcularse porque **cada llamador lo
  /// deriva de una fuente distinta**, y no es un descuido:
  ///   - al cerrar el partido, de las estadísticas vivas en memoria
  ///     (titular, en cancha, puntos o faltas);
  ///   - al subirlo más tarde, de si aparece en algún evento persistido.
  /// Unificarlos cambiaría lo que se envía. Lo que sí se comparte es la forma.
  static Map<String, dynamic> mapRoster(
    RosterEntry roster, {
    required int playerId,
    required bool hasPlayed,
  }) {
    return {
      'player_id': playerId,
      'team_side': roster.teamSide,
      'is_starter': roster.isStarter ? 1 : 0,
      'jersey_number': roster.jerseyNumber,
      'is_captain': roster.isCaptain ? 1 : 0,
      'played': hasPlayed ? 1 : 0,
      'attended': roster.attended ? 1 : 0,
    };
  }

  /// Un equipo que no se presentó no jugó, por muchos titulares que se hayan
  /// marcado en la UI para poder avanzar. El forfeit manda.
  static bool teamForfeited(String teamSide, String forfeitStatus) {
    if (forfeitStatus == ForfeitStatus.both) return true;
    if (teamSide == TeamSide.home) {
      return forfeitStatus == ForfeitStatus.teamA;
    }
    return forfeitStatus == ForfeitStatus.teamB;
  }

  /// Fecha en el formato que espera el backend: `YYYY-MM-DD HH:MM:SS`.
  ///
  /// Estaba escrita a mano, con la misma cadena de `padLeft`, en el cierre del
  /// partido y en la subida diferida. Dos copias de un formato que el servidor
  /// parsea: si una se desviara, el backend rechazaría esas actas.
  static String backendDateTime(DateTime when) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${when.year}-${two(when.month)}-${two(when.day)} '
        '${two(when.hour)}:${two(when.minute)}:${two(when.second)}';
  }

  static int _pointsOf(String cleanType) => switch (cleanType) {
    'POINT_1' || 'FREE_THROW' => 1,
    EventType.point2 => 2,
    EventType.point3 => 3,
    _ => 0,
  };
}
