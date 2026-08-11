// Regresión del crash que destapó el solapamiento de `EventType`.
//
// `addTeamFoul` guarda la técnica con `playerId: "Entrenador"` (un nombre,
// no un id), y `undoLastFoul` hacía `playerStats[lastFoul.playerId]!`. Como
// `isPlayerFoul('C')` devolvía `true` —cualquier tipo de <= 2 caracteres lo
// era—, ese evento entraba en el filtro y el `!` reventaba.
//
// Se reproduce con el flujo real de la mesa: técnica al entrenador, deshacer.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';

void main() {
  late AppDatabase db;
  late MatchGameController controller;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.matches)
        .insert(
          MatchesCompanion.insert(
            id: const Value('M1'),
            teamAName: 'Lobos',
            teamBName: 'Pumas',
          ),
        );
    controller = MatchGameController(db.matchesDao);
    controller.initializeNewMatch(
      matchId: 'M1',
      fixtureId: 'F1',
      rosterA: const [],
      rosterB: const [],
      startersA: const {},
      startersB: const {},
      tournamentId: 1,
      venueId: 1,
      teamAId: 3,
      teamBId: 4,
      mainReferee: 'Juan',
      auxReferee: 'Ana',
      scorekeeper: 'Luis',
    );
  });

  // El controller persiste en segundo plano sin `await`. Si el test termina
  // antes, la escritura pendiente choca con la base ya cerrada.
  tearDown(() async {
    await pumpEventQueue();
    controller.dispose();
    await db.close();
  });

  test('deshacer una técnica al entrenador no revienta', () async {
    controller.addTeamFoul(TeamSide.home, EventType.coach);
    expect(controller.state.scoreLog, hasLength(1));

    // Antes de la Fase 9 esto lanzaba un null assertion: "Entrenador" no es
    // una clave de playerStats.
    controller.undoLastFoul();

    expect(controller.state.scoreLog, isEmpty);
  });

  test('deshace la ÚLTIMA falta, no la última de jugador', () async {
    // Si el filtro solo mirara faltas de jugador, este deshacer se llevaría
    // la personal y dejaría la técnica puesta, que no es lo que espera quien
    // acaba de pitarla.
    controller.addTeamFoul(TeamSide.home, EventType.coach);

    final log = controller.state.scoreLog;
    expect(log.single.type, EventType.coach);

    controller.undoLastFoul();
    expect(controller.state.scoreLog, isEmpty);
  });

  test(
    'la técnica de banquillo suma a las faltas de equipo del período',
    () async {
      // En FIBA cuenta igual que una personal. Salía bien por accidente:
      // isPlayerFoul aceptaba 'C' por tener 2 caracteres.
      expect(teamFoulsOf(controller.state, TeamSide.home), 0);

      controller.addTeamFoul(TeamSide.home, EventType.coach);

      expect(teamFoulsOf(controller.state, TeamSide.home), 1);
      expect(
        teamFoulsOf(controller.state, TeamSide.away),
        0,
        reason: 'la técnica es del local, no del visitante',
      );
    },
  );

  test('el mismo evento cuenta igual en vivo que restaurado', () async {
    // En vivo el tipo es 'C'; al reabrir el partido vuelve de la base como
    // 'C_A'. Antes uno contaba y el otro no, así que el mismo partido
    // mostraba faltas distintas antes y después de restaurarlo.
    controller.addTeamFoul(TeamSide.home, EventType.coach);
    final live = teamFoulsOf(controller.state, TeamSide.home);

    final event = controller.state.scoreLog.single;
    final restored = controller.state.copyWith(
      scoreLog: [
        ScoreEvent(
          period: event.period,
          teamId: event.teamId,
          playerId: event.playerId,
          playerNumber: event.playerNumber,
          points: event.points,
          scoreAfter: event.scoreAfter,
          type: EventType.teamFoul(EventType.coach, TeamSide.home),
        ),
      ],
    );

    expect(teamFoulsOf(restored, TeamSide.home), live);
  });
}
