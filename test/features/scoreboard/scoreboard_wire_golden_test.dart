// GOLDEN DEL CABLE DEL MARCADOR — paso 0 de la Fase 7 (invariante I4).
//
// La Fase 7 saca `MatchState` del archivo del controller y mueve la
// serialización a la feature de marcador. Nada de eso debe cambiar lo que
// viaja por el WebSocket: una TV o una tablet con la build ANTERIOR tiene que
// seguir decodificando lo que emite la build nueva.
//
// Se congela antes de tocar nada, igual que se hizo con el payload del acta.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/scoreboard/domain/scoreboard_payload.dart';

// Importa MatchState por donde vive HOY. Tras el movimiento este import
// cambia, pero las CLAVES del JSON no pueden cambiar: eso es lo que el test
// vigila.
import 'package:myapp/features/match/domain/entities/match_state.dart';

/// Un estado con todos los campos que cruzan el cable puestos a valores
/// distintos entre sí, para que un intercambio de claves se note.
MatchState get _state => const MatchState(
  matchId: 'M1',
  scoreA: 55,
  scoreB: 48,
  timeLeft: Duration(seconds: 214),
  isRunning: true,
  currentPeriod: 3,
  possession: 'A',
  teamATimeouts1: ['1'],
  teamATimeouts2: ['1', '2'],
  teamAOTTimeouts: [],
  teamBTimeouts1: [],
  teamBTimeouts2: ['1'],
  teamBOTTimeouts: ['1'],
  forfeitStatus: 'NONE',
  observaciones: 'Sin novedad',
);

void main() {
  group('Contrato de cable (I4)', () {
    test('las claves emitidas no cambian', () {
      final payload = ScoreboardPayload.fromMatch(
        _state,
        const ScoreboardMeta(teamAName: 'Lobos', teamBName: 'Pumas'),
      );

      final json = payload.toJson();
      expect(json.keys.toSet(), {
        'v',
        'state',
        'teamAName',
        'teamBName',
        'teamAFouls',
        'teamBFouls',
        'isFinished',
      });

      // El subconjunto que viaja dentro de `state` es deliberado: la TV pinta
      // marcador, reloj, período, posesión y tiempos fuera. Las faltas van
      // YA CALCULADAS fuera (`teamAFouls`), así que el receptor no necesita
      // `scoreLog` ni `playerStats`.
      expect((json['state']! as Map).keys.toSet(), {
        'scoreA',
        'scoreB',
        'timeLeft',
        'isRunning',
        'currentPeriod',
        'possession',
        'teamATimeouts1',
        'teamATimeouts2',
        'teamAOTTimeouts',
        'teamBTimeouts1',
        'teamBTimeouts2',
        'teamBOTTimeouts',
        'forfeitStatus',
        'observaciones',
      });
    });

    test('la versión del esquema sigue siendo 1', () {
      // Subirla dejaría en negro a cualquier receptor con la build vieja.
      expect(ScoreboardPayload.schemaVersion, 1);
    });

    test('el reloj viaja en SEGUNDOS, no como Duration', () {
      final json = ScoreboardPayload.fromMatch(
        _state,
        const ScoreboardMeta(teamAName: 'A', teamBName: 'B'),
      ).toJson();

      expect((json['state']! as Map)['timeLeft'], 214);
    });

    test('ida y vuelta: lo emitido se decodifica igual', () {
      final original = ScoreboardPayload.fromMatch(
        _state,
        const ScoreboardMeta(
          teamAName: 'Lobos',
          teamBName: 'Pumas',
          isFinished: true,
        ),
      );

      final decoded = ScoreboardPayload.tryDecode(original.encode())!;

      expect(decoded.teamAName, 'Lobos');
      expect(decoded.teamBName, 'Pumas');
      expect(decoded.isFinished, isTrue);
      expect(decoded.state.scoreA, 55);
      expect(decoded.state.scoreB, 48);
      expect(decoded.state.timeLeft, const Duration(seconds: 214));
      expect(decoded.state.currentPeriod, 3);
      expect(decoded.state.possession, 'A');
      expect(decoded.state.teamATimeouts2, ['1', '2']);
      expect(decoded.state.forfeitStatus, 'NONE');
    });
  });

  group('Compatibilidad hacia atrás', () {
    test('decodifica un payload v1 capturado tal cual', () {
      // Este string es lo que emite la build ACTUAL. Si la Fase 7 cambiara
      // una clave, este test se cae: es exactamente lo que una TV con la
      // build vieja recibiría.
      const captured =
          '{"v":1,"state":{"scoreA":55,"scoreB":48,"timeLeft":214,'
          '"isRunning":true,"currentPeriod":3,"possession":"A",'
          '"teamATimeouts1":["1"],"teamATimeouts2":["1","2"],'
          '"teamAOTTimeouts":[],"teamBTimeouts1":[],"teamBTimeouts2":["1"],'
          '"teamBOTTimeouts":["1"],"forfeitStatus":"NONE",'
          '"observaciones":"Sin novedad"},"teamAName":"Lobos",'
          '"teamBName":"Pumas","teamAFouls":2,"teamBFouls":1,'
          '"isFinished":false}';

      final decoded = ScoreboardPayload.tryDecode(captured)!;
      expect(decoded.state.scoreA, 55);
      expect(decoded.state.currentPeriod, 3);
      expect(decoded.teamAFouls, 2);
      expect(decoded.teamBName, 'Pumas');
    });

    test('decodifica la forma legacy plana, sin envoltorio', () {
      // Antes el mapa ERA el MatchState. Se sigue aceptando para que emisor y
      // receptor puedan actualizarse en momentos distintos.
      const legacy = '{"scoreA":10,"scoreB":8,"currentPeriod":2}';

      final decoded = ScoreboardPayload.tryDecode(legacy)!;
      expect(decoded.state.scoreA, 10);
      expect(decoded.state.currentPeriod, 2);
      expect(decoded.teamAName, 'Equipo A', reason: 'valor por defecto');
    });

    test('un mensaje basura devuelve null en vez de reventar', () {
      // Cualquiera puede escribir en el socket abierto de la LAN.
      expect(ScoreboardPayload.tryDecode('no soy json'), isNull);
      expect(ScoreboardPayload.tryDecode('[1,2,3]'), isNull);
    });

    test('un payload con campos DE MÁS se ignora sin romperse', () {
      // Garantiza que se puedan añadir campos de forma aditiva más adelante
      // sin dejar en negro a los receptores actuales.
      final withExtras =
          jsonDecode(
                ScoreboardPayload.fromMatch(
                  _state,
                  const ScoreboardMeta(teamAName: 'A', teamBName: 'B'),
                ).encode(),
              )
              as Map<String, dynamic>;
      withExtras['campoDelFuturo'] = {'algo': 1};
      (withExtras['state']! as Map)['otroCampo'] = 99;

      final decoded = ScoreboardPayload.tryDecode(jsonEncode(withExtras));
      expect(decoded, isNotNull);
      expect(decoded!.state.scoreA, 55);
    });
  });
}
