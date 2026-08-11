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

    test("'B' significa DOS cosas distintas según el campo", () {
      // Esta colisión es una trampa real: al sustituir los literales por
      // constantes en la Fase 9, un reemplazo ciego de `== 'B'` convirtió
      // el filtro de faltas de banca del acta en una comparación de equipo.
      //
      // `scoreLog.type == 'B'`      -> falta de BANCA  (EventType.bench)
      // `scoreLog.teamId == 'B'`    -> equipo VISITANTE (TeamSide.away)
      //
      // Se dejan iguales a propósito —son los valores que ya viven en las
      // bases instaladas y en el backend—, pero quien lea un `'B'` suelto
      // tiene que mirar de qué campo cuelga.
      expect(TeamSide.away, EventType.bench);
      expect(
        TeamSide.away == EventType.bench,
        isTrue,
        reason: 'si alguna deja de ser "B", revisa los dos usos por separado',
      );
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

    test('affects entiende la forma larga', () {
      expect(ForfeitStatus.affects(ForfeitStatus.teamA, TeamSide.home), isTrue);
      expect(
        ForfeitStatus.affects(ForfeitStatus.teamA, TeamSide.away),
        isFalse,
      );
      expect(ForfeitStatus.affects(ForfeitStatus.teamB, TeamSide.away), isTrue);
      expect(
        ForfeitStatus.affects(ForfeitStatus.teamB, TeamSide.home),
        isFalse,
      );
    });

    test('affects entiende tambien el lado pelado', () {
      // `playersPendingAttendanceByTeam(forfeitOverride:)` recibe 'A'/'B'
      // desde la pantalla de control, no 'TEAM_A'/'TEAM_B'. El generador del
      // acta solo entendia la forma larga: con un override 'A' no habria
      // vaciado el roster del local.
      expect(ForfeitStatus.affects(TeamSide.home, TeamSide.home), isTrue);
      expect(ForfeitStatus.affects(TeamSide.home, TeamSide.away), isFalse);
      expect(ForfeitStatus.affects(TeamSide.away, TeamSide.away), isTrue);
    });

    test('BOTH afecta a los dos, y NONE a ninguno', () {
      expect(ForfeitStatus.affects(ForfeitStatus.both, TeamSide.home), isTrue);
      expect(ForfeitStatus.affects(ForfeitStatus.both, TeamSide.away), isTrue);
      expect(ForfeitStatus.affects(ForfeitStatus.none, TeamSide.home), isFalse);
      expect(ForfeitStatus.affects(ForfeitStatus.none, TeamSide.away), isFalse);
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

    // CORREGIDO EN LA FASE 9.
    //
    // Hasta aquí este test congelaba el comportamiento contrario: 'C' y 'B'
    // (la forma «en vivo» de una técnica de banquillo) caían en AMBOS
    // predicados, porque isPlayerFoul aceptaba cualquier tipo de <= 2
    // caracteres. Se dejó escrito en la Fase 0 como deuda con dueño, con la
    // corrección planificada para la Fase 9 y este test como red.
    //
    // Ahora los predicados son disjuntos.
    test('un tipo de falta no puede ser de jugador Y de banquillo', () {
      for (final type in ['C', 'B', 'C_A', 'B_B']) {
        expect(EventType.isTeamFoul(type), isTrue, reason: 'para "$type"');
        expect(
          EventType.isPlayerFoul(type),
          isFalse,
          reason: '"$type" es técnica de banquillo, no falta de jugador',
        );
      }

      for (final type in ['P', 'P1', 'T1', 'U', 'D', 'FOUL']) {
        expect(EventType.isPlayerFoul(type), isTrue, reason: 'para "$type"');
        expect(EventType.isTeamFoul(type), isFalse, reason: 'para "$type"');
      }
    });

    test('countsTowardTeamFouls suma las personales y las técnicas', () {
      // En FIBA la técnica al entrenador suma al contador del período igual
      // que una personal. Este predicado existe porque isPlayerFoul ya no
      // las mezcla, y el marcador sí las necesita juntas.
      for (final type in ['P', 'U', 'C', 'B', 'C_A', 'B_B']) {
        expect(
          EventType.countsTowardTeamFouls(type),
          isTrue,
          reason: 'para "$type"',
        );
      }

      for (final type in [
        'POINT_2',
        'SUB_A_OUT_1_IN_2',
        'TIMEOUT_A',
        'POSS_A',
      ]) {
        expect(
          EventType.countsTowardTeamFouls(type),
          isFalse,
          reason: 'para "$type"',
        );
      }
    });

    test('la forma en vivo y la persistida se clasifican igual', () {
      // El bug de fondo era la asimetría: en vivo la técnica es 'C' y al
      // reabrir el partido vuelve de la base como 'C_A'. Antes, 'C' contaba
      // en las faltas de equipo y 'C_A' no, así que el mismo partido mostraba
      // números distintos antes y después de restaurarlo.
      expect(
        EventType.countsTowardTeamFouls('C'),
        EventType.countsTowardTeamFouls('C_A'),
      );
      expect(EventType.isPlayerFoul('B'), EventType.isPlayerFoul('B_B'));
    });
  });
}
