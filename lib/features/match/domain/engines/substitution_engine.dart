import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';

/// Los cambios de jugador.
///
/// Vivían en un método de 79 líneas con la rama del equipo A y la del B
/// duplicadas casi palabra por palabra: cualquier corrección había que
/// aplicarla dos veces y era fácil que se desincronizaran.
abstract final class SubstitutionEngine {
  /// Mete a [playerInId] y saca a [playerOutId].
  ///
  /// Devuelve `null` si el cambio no es válido, para que el llamador no lo
  /// registre ni lo meta en el historial de deshacer.
  static MatchState? substitute(
    MatchState state, {
    required String teamId,
    required String playerOutId,
    required String playerInId,
  }) {
    // Cambiar a un jugador por sí mismo dejaría un evento SUB en el acta que
    // no significa nada, y al reproducirlo en el restore lo sacaría de cancha.
    if (playerOutId == playerInId) return null;

    final isTeamA = teamId == TeamSide.home;
    final onCourt = List<String>.from(
      isTeamA ? state.teamAOnCourt : state.teamBOnCourt,
    );
    final bench = List<String>.from(
      isTeamA ? state.teamABench : state.teamBBench,
    );

    // El que sale tiene que estar en cancha y el que entra en banca. Sin esto
    // un doble toque duplica al jugador en la lista.
    if (!onCourt.contains(playerOutId)) return null;
    if (!bench.contains(playerInId)) return null;

    onCourt
      ..remove(playerOutId)
      ..add(playerInId);
    bench
      ..remove(playerInId)
      ..add(playerOutId);

    final stats = Map<String, PlayerStats>.from(state.playerStats);
    final out = stats[playerOutId];
    if (out != null) {
      stats[playerOutId] = out.copyWith(isOnCourt: false);
    }
    final incoming = stats[playerInId];
    if (incoming != null) {
      // Entrar a cancha cuenta como haber jugado, aunque no anote ni cometa
      // falta: en el acta debe figurar como participante.
      stats[playerInId] = incoming.copyWith(isOnCourt: true, hasPlayed: true);
    }

    final scoreLog = List<ScoreEvent>.from(state.scoreLog)
      ..add(
        ScoreEvent(
          period: state.currentPeriod,
          teamId: teamId,
          // `playerId` es quien SALE y `playerNumber` quien ENTRA: el evento
          // reaprovecha esos dos campos porque `ScoreEvent` no tiene un hueco
          // propio para un cambio. Deshacer un cambio depende de esta
          // convención.
          playerId: playerOutId,
          dbPlayerId: 0,
          playerNumber: playerInId,
          points: 0,
          scoreAfter: 0,
          type: 'SUB',
        ),
      );

    return state.copyWith(
      teamAOnCourt: isTeamA ? onCourt : state.teamAOnCourt,
      teamABench: isTeamA ? bench : state.teamABench,
      teamBOnCourt: isTeamA ? state.teamBOnCourt : onCourt,
      teamBBench: isTeamA ? state.teamBBench : bench,
      playerStats: stats,
      scoreLog: scoreLog,
    );
  }
}
