import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';

/// Resultado de intentar registrar una acción de un jugador.
///
/// Se devuelve un resultado explícito en vez de `MatchState?` porque **por qué**
/// se rechazó importa: el controller no debe persistir ni registrar el evento
/// si la acción no se aplicó, y hoy eso se decidía con tres `return` mudos
/// dentro de un método de 90 líneas.
sealed class ScoreOutcome {
  const ScoreOutcome();
}

/// La acción se aplicó. [state] es el estado nuevo.
final class ScoreApplied extends ScoreOutcome {
  const ScoreApplied(this.state, {required this.event});

  final MatchState state;

  /// El evento que se añadió al log, o `null` si la acción no genera uno
  /// (p.ej. una corrección de 0 puntos y 0 faltas).
  final ScoreEvent? event;
}

/// La acción se rechazó por una regla. El estado no cambia.
final class ScoreRejected extends ScoreOutcome {
  const ScoreRejected(this.reason);

  final ScoreRejection reason;
}

enum ScoreRejection {
  /// No hay estadísticas para ese jugador: no está en el partido.
  unknownPlayer,

  /// El jugador no pertenece al equipo indicado. Protege contra anotar un
  /// punto al equipo equivocado por un toque en la pantalla contraria.
  wrongTeam,

  /// Cinco faltas: queda descalificado y no puede sumar más.
  disqualified,
}

/// Las reglas de anotación y falta de un jugador.
///
/// Función **pura** sobre [MatchState]: sin base de datos, sin red, sin
/// `Timer`. Vivía dentro de `MatchGameController.updateStats`, mezclada con la
/// persistencia y el registro de eventos, así que las reglas de baloncesto
/// —que son el corazón de la app— no tenían ni un test.
abstract final class ScoreEngine {
  /// Máximo de faltas personales antes de la descalificación.
  static const int foulLimit = 5;

  /// Registra puntos y/o una falta a un jugador.
  ///
  /// [foulType] es el código de la falta (P, T1, U, D…); si no viene se usa
  /// `'P'`, que es la falta personal simple.
  static ScoreOutcome applyPlayerAction(
    MatchState state, {
    required String teamId,
    required String playerId,
    int points = 0,
    int fouls = 0,
    String? foulType,
  }) {
    final current = state.playerStats[playerId];
    if (current == null) {
      return const ScoreRejected(ScoreRejection.unknownPlayer);
    }

    if (!_belongsTo(state, playerId, teamId)) {
      return const ScoreRejected(ScoreRejection.wrongTeam);
    }

    final isAction = points > 0 || fouls > 0;
    if (current.fouls >= foulLimit && isAction) {
      return const ScoreRejected(ScoreRejection.disqualified);
    }

    final newScoreA = state.scoreA + (teamId == TeamSide.home ? points : 0);
    final newScoreB = state.scoreB + (teamId == TeamSide.away ? points : 0);
    final scoreAfter = teamId == TeamSide.home ? newScoreA : newScoreB;

    // La lista interna se copia, no se muta: el estado anterior sigue en el
    // historial de deshacer y comparte el mapa.
    final periodScores = Map<int, List<int>>.from(state.periodScores);
    final currentPeriod = List<int>.from(
      periodScores[state.currentPeriod] ?? const [0, 0],
    );
    if (points > 0) {
      currentPeriod[teamId == TeamSide.home ? 0 : 1] += points;
    }
    periodScores[state.currentPeriod] = currentPeriod;

    final foulDetails = List<String>.from(current.foulDetails);
    if (fouls > 0) foulDetails.add(foulType ?? 'P');

    final playerStats = Map<String, PlayerStats>.from(state.playerStats);
    playerStats[playerId] = current.copyWith(
      points: current.points + points,
      fouls: current.fouls + fouls,
      foulDetails: foulDetails,
      // Si se le registra una acción, participó en el partido.
      hasPlayed: true,
    );

    final scoreLog = List<ScoreEvent>.from(state.scoreLog);
    ScoreEvent? event;
    if (isAction) {
      event = ScoreEvent(
        period: state.currentPeriod,
        teamId: teamId,
        playerId: playerId,
        dbPlayerId: current.dbId,
        playerNumber: current.playerNumber,
        points: points,
        scoreAfter: scoreAfter,
        type: points > 0 ? 'POINT_$points' : (foulType ?? 'FOUL'),
      );
      scoreLog.add(event);
    }

    return ScoreApplied(
      state.copyWith(
        scoreA: newScoreA,
        scoreB: newScoreB,
        periodScores: periodScores,
        playerStats: playerStats,
        scoreLog: scoreLog,
      ),
      event: event,
    );
  }

  /// Un jugador cuenta para su equipo tanto en cancha como en banca.
  static bool _belongsTo(MatchState state, String playerId, String teamId) {
    if (teamId == TeamSide.home) {
      return state.teamAOnCourt.contains(playerId) ||
          state.teamABench.contains(playerId);
    }
    return state.teamBOnCourt.contains(playerId) ||
        state.teamBBench.contains(playerId);
  }
}
