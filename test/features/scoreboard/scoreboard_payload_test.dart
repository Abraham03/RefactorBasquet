import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/scoreboard/domain/scoreboard_payload.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';

void main() {
  const meta = ScoreboardMeta(teamAName: 'Lobos', teamBName: 'Águilas');

  group('ScoreboardPayload', () {
    test('round-trip conserva los campos', () {
      const state = MatchState(
        scoreA: 44,
        scoreB: 38,
        timeLeft: Duration(minutes: 3, seconds: 12),
        isRunning: true,
        currentPeriod: 3,
        possession: 'A',
      );

      final original = ScoreboardPayload.fromMatch(state, meta);
      final restored = ScoreboardPayload.fromJson(
        jsonDecode(original.encode()) as Map<String, dynamic>,
      );

      expect(restored.state.scoreA, 44);
      expect(restored.state.scoreB, 38);
      expect(restored.state.timeLeft, const Duration(minutes: 3, seconds: 12));
      expect(restored.state.isRunning, isTrue);
      expect(restored.state.currentPeriod, 3);
      expect(restored.state.possession, 'A');
      expect(restored.teamAName, 'Lobos');
      expect(restored.teamBName, 'Águilas');
    });

    test('calcula las faltas de equipo del período en curso', () {
      const state = MatchState(
        currentPeriod: 2,
        scoreLog: [
          // Período en curso: cuentan.
          ScoreEvent(
              period: 2,
              teamId: 'A',
              playerId: 'p1',
              playerNumber: '4',
              points: 0,
              scoreAfter: 0,
              type: 'FOUL_P'),
          ScoreEvent(
              period: 2,
              teamId: 'A',
              playerId: 'p2',
              playerNumber: '5',
              points: 0,
              scoreAfter: 0,
              type: 'FOUL_P'),
          // Período anterior: no cuenta.
          ScoreEvent(
              period: 1,
              teamId: 'A',
              playerId: 'p3',
              playerNumber: '6',
              points: 0,
              scoreAfter: 0,
              type: 'FOUL_P'),
          // Otro equipo.
          ScoreEvent(
              period: 2,
              teamId: 'B',
              playerId: 'p9',
              playerNumber: '9',
              points: 0,
              scoreAfter: 0,
              type: 'FOUL_P'),
          // Canasta, no falta.
          ScoreEvent(
              period: 2,
              teamId: 'A',
              playerId: 'p1',
              playerNumber: '4',
              points: 2,
              scoreAfter: 2,
              type: 'POINT'),
        ],
      );

      final payload = ScoreboardPayload.fromMatch(state, meta);
      expect(payload.teamAFouls, 2);
      expect(payload.teamBFouls, 1);
    });

    test('acepta la forma legacy (mapa plano = MatchState)', () {
      const state = MatchState(scoreA: 10, scoreB: 7, currentPeriod: 2);
      final legacy = jsonEncode(state.toScoreboardJson());

      final payload = ScoreboardPayload.tryDecode(legacy);
      expect(payload, isNotNull);
      expect(payload!.state.scoreA, 10);
      expect(payload.state.scoreB, 7);
      expect(payload.teamAName, 'Equipo A');
      expect(payload.teamAFouls, 0);
    });

    test('tryDecode devuelve null con basura', () {
      for (final bad in ['', 'no es json', '[1,2,3]', '"texto"', '{']) {
        expect(ScoreboardPayload.tryDecode(bad), isNull,
            reason: 'debería rechazar "$bad"');
      }
    });

    test('el payload lleva la versión de esquema', () {
      final payload = ScoreboardPayload.fromMatch(const MatchState(), meta);
      final json = jsonDecode(payload.encode()) as Map<String, dynamic>;
      expect(json['v'], ScoreboardPayload.schemaVersion);
    });
  });

  group('teamFoulsOf', () {
    test('sin eventos devuelve 0', () {
      expect(teamFoulsOf(const MatchState(), 'A'), 0);
    });
  });
}
