// Test de CARACTERIZACIÓN de las constantes de dominio del partido.
//
// No afirma lo que el código "debería" hacer: congela lo que hace HOY.
// `EventType` es la única fuente de verdad de los tipos de evento y sus
// predicados alimentan el controller, el generador de PDF y la sincronización.
// Cualquier cambio de comportamiento aquí se propaga al acta impresa y al
// payload que recibe el backend, así que se blinda antes de mover un archivo.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
import 'package:myapp/core/constants/match_status.dart';

void main() {
  group('TeamSide', () {
    test('los lados son los literales que espera el backend', () {
      expect(TeamSide.home, 'A');
      expect(TeamSide.away, 'B');
    });
  });

  group('MatchStatus', () {
    test('los estados son los literales que espera el backend', () {
      expect(MatchStatus.scheduled, 'SCHEDULED');
      expect(MatchStatus.inProgress, 'IN_PROGRESS');
      expect(MatchStatus.finished, 'FINISHED');
      expect(MatchStatus.deleted, 'DELETED');
    });
  });

  group('ForfeitStatus', () {
    test('los estados de inasistencia son los del backend', () {
      expect(ForfeitStatus.none, 'NONE');
      expect(ForfeitStatus.teamA, 'TEAM_A');
      expect(ForfeitStatus.teamB, 'TEAM_B');
      expect(ForfeitStatus.both, 'BOTH');
    });
  });

  group('EventType — constructores de tipos compuestos', () {
    test('pointFor arma el tipo de puntos', () {
      expect(EventType.pointFor(1), 'POINT_1');
      expect(EventType.pointFor(2), 'POINT_2');
      expect(EventType.pointFor(3), 'POINT_3');
    });

    test('subEvent embebe lado, jugador que sale y jugador que entra', () {
      expect(
        EventType.subEvent(side: 'A', outId: '12', inId: '7'),
        'SUB_A_OUT_12_IN_7',
      );
    });

    test('timeoutFor y possessionFor', () {
      expect(EventType.timeoutFor('A'), 'TIMEOUT_A');
      expect(EventType.possessionFor('B'), 'POSS_B');
      expect(EventType.possNone, 'POSS_NONE');
    });

    test('teamFoul persiste el código con sufijo de lado', () {
      expect(EventType.teamFoul('C', 'A'), 'C_A');
      expect(EventType.teamFoul('B', 'B'), 'B_B');
    });
  });

  group('EventType — pointsOf', () {
    test('mapea los tipos de punto a su valor', () {
      expect(EventType.pointsOf('POINT_1'), 1);
      expect(EventType.pointsOf('POINT_2'), 2);
      expect(EventType.pointsOf('POINT_3'), 3);
    });

    test('todo lo que no es punto vale 0', () {
      for (final type in [
        'FOUL',
        'P',
        'C_A',
        'SUB_A_OUT_1_IN_2',
        'TIMEOUT_A',
      ]) {
        expect(EventType.pointsOf(type), 0, reason: 'para "$type"');
      }
    });
  });

  group('EventType — predicados', () {
    test('isSub reconoce la forma en vivo y la persistida', () {
      expect(EventType.isSub('SUB'), isTrue);
      expect(EventType.isSub('SUB_A_OUT_12_IN_7'), isTrue);
      expect(EventType.isSub('POINT_2'), isFalse);
    });

    test('isTimeout usa contains, no startsWith', () {
      expect(EventType.isTimeout('TIMEOUT_A'), isTrue);
      expect(EventType.isTimeout('TIMEOUT'), isTrue);
      expect(EventType.isTimeout('P'), isFalse);
    });

    test('isPossession solo acepta el prefijo POSS_', () {
      expect(EventType.isPossession('POSS_A'), isTrue);
      expect(EventType.isPossession('POSS_NONE'), isTrue);
      expect(EventType.isPossession('POSS'), isFalse);
    });

    test('isPlayerFoul acepta códigos cortos y cualquier cosa con FOUL', () {
      for (final type in ['P', 'P1', 'T1', 'U', 'D', 'FOUL']) {
        expect(EventType.isPlayerFoul(type), isTrue, reason: 'para "$type"');
      }
    });

    test('isPlayerFoul descarta puntos, cambios, timeouts y posesión', () {
      for (final type in [
        'POINT_2',
        'SUB_A_OUT_1_IN_2',
        'TIMEOUT_A',
        'POSS_A',
        'C_A',
        'B_B',
      ]) {
        expect(EventType.isPlayerFoul(type), isFalse, reason: 'para "$type"');
      }
    });

    test('isTeamFoul cubre la forma en vivo y la persistida con sufijo', () {
      for (final type in ['C', 'B', 'C_A', 'B_B']) {
        expect(EventType.isTeamFoul(type), isTrue, reason: 'para "$type"');
      }
      expect(EventType.isTeamFoul('P'), isFalse);
      expect(EventType.isTeamFoul('POINT_2'), isFalse);
    });

    // Comportamiento actual documentado, NO deseado: 'C' y 'B' sin sufijo
    // (la forma "en vivo" de una falta de banca) caen en AMBOS predicados,
    // porque isPlayerFoul acepta cualquier tipo de <= 2 caracteres.
    // Quien filtre con isPlayerFoul antes que con isTeamFoul contará una
    // falta de banca como falta personal de jugador.
    //
    // Se congela aquí para que el refactor no lo cambie por accidente: si
    // este test empieza a fallar, es que alguien alteró la clasificación de
    // faltas, lo cual cambia el acta impresa y el payload al backend.
    // La corrección va en la Fase 9, deliberadamente y con este test como red.
    test('solapamiento conocido: C y B en vivo son ambos predicados', () {
      expect(EventType.isPlayerFoul('C'), isTrue);
      expect(EventType.isTeamFoul('C'), isTrue);
      expect(EventType.isPlayerFoul('B'), isTrue);
      expect(EventType.isTeamFoul('B'), isTrue);

      // Con sufijo de lado sí quedan bien separados.
      expect(EventType.isPlayerFoul('C_A'), isFalse);
      expect(EventType.isTeamFoul('C_A'), isTrue);
    });
  });
}
