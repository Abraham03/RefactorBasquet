// Las reglas de tiempos muertos.
//
// Vivían repartidas entre tres métodos del controller, con un `if` de período
// en cada uno, y no tenían ni un test — pese a que lo que escriben acaba
// impreso en el acta que firman los árbitros.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/match/domain/engines/timeout_engine.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';

MatchState stateIn(
  int period, {
  Duration timeLeft = const Duration(minutes: 8),
  List<String> a1 = const [],
  List<String> a2 = const [],
  List<String> aOt = const [],
}) {
  return MatchState(
    matchId: 'M1',
    currentPeriod: period,
    timeLeft: timeLeft,
    teamATimeouts1: a1,
    teamATimeouts2: a2,
    teamAOTTimeouts: aOt,
  );
}

void main() {
  group('Primera mitad — dos por equipo', () {
    test('concede el primero y el segundo', () {
      var state = TimeoutEngine.grant(stateIn(1), 'A')!;
      expect(state.teamATimeouts1, hasLength(1));

      state = TimeoutEngine.grant(state, 'A')!;
      expect(state.teamATimeouts1, hasLength(2));
    });

    test('el tercero se rechaza', () {
      final state = stateIn(1, a1: const ['8', '4']);
      expect(TimeoutEngine.grant(state, 'A'), isNull);
    });

    test('el cupo es por equipo, no compartido', () {
      final state = TimeoutEngine.grant(stateIn(1, a1: const ['8', '4']), 'B');
      expect(state, isNotNull, reason: 'B no ha gastado ninguno');
    });
  });

  group('Segunda mitad — tres, y cupo independiente', () {
    test('lo no gastado en la primera mitad NO se arrastra', () {
      // Un equipo que no pidió ninguno en la primera mitad no empieza la
      // segunda con cinco.
      final state = TimeoutEngine.grant(stateIn(3), 'A')!;

      expect(state.teamATimeouts2, hasLength(1));
      expect(state.teamATimeouts1, isEmpty, reason: 'son cupos distintos');
    });

    test('el cuarto se rechaza', () {
      final state = stateIn(4, a2: const ['8', '5', '2']);
      expect(TimeoutEngine.grant(state, 'A'), isNull);
    });
  });

  group('Clutch time — no se pueden guardar todos para el final', () {
    test('quema uno si el equipo no había gastado ninguno', () {
      // A falta de 2:00 del último período, el que llega con los tres
      // intactos pierde uno: se anota "X" y el que pide es el segundo.
      final state = TimeoutEngine.grant(
        stateIn(4, timeLeft: const Duration(minutes: 2)),
        'A',
      )!;

      expect(state.teamATimeouts2, ['X', '2']);
    });

    test('al que ya había gastado uno no se le quema nada', () {
      final state = TimeoutEngine.grant(
        stateIn(4, timeLeft: const Duration(minutes: 2), a2: const ['7']),
        'A',
      )!;

      expect(state.teamATimeouts2, ['7', '2']);
    });

    test('antes de los dos últimos minutos no se quema', () {
      final state = TimeoutEngine.grant(
        stateIn(4, timeLeft: const Duration(seconds: 121)),
        'A',
      )!;

      expect(state.teamATimeouts2, hasLength(1));
      expect(state.teamATimeouts2.first, isNot('X'));
    });

    test('en el tercer período tampoco, aunque queden 2 minutos', () {
      final state = TimeoutEngine.grant(
        stateIn(3, timeLeft: const Duration(minutes: 1)),
        'A',
      )!;

      expect(state.teamATimeouts2, hasLength(1));
      expect(state.teamATimeouts2.first, isNot('X'));
    });
  });

  group('Prórroga — uno por prórroga jugada', () {
    test('en la primera prórroga solo se concede uno', () {
      final first = TimeoutEngine.grant(stateIn(5), 'A')!;
      expect(first.teamAOTTimeouts, hasLength(1));

      expect(
        TimeoutEngine.grant(first, 'A'),
        isNull,
        reason: 'el segundo tendría que esperar a la 2ª prórroga',
      );
    });

    test('en la segunda prórroga se puede tener el segundo', () {
      final state = TimeoutEngine.grant(stateIn(6, aOt: const ['3']), 'A');
      expect(state!.teamAOTTimeouts, hasLength(2));
    });

    test(
      'hay un tope absoluto de tres, por muchas prórrogas que se jueguen',
      () {
        final state = stateIn(9, aOt: const ['3', '2', '1']);
        expect(TimeoutEngine.grant(state, 'A'), isNull);
      },
    );
  });

  group('El minuto que se anota en el acta', () {
    test('el reloj entero anota su minuto', () {
      expect(TimeoutEngine.minuteMark(const Duration(minutes: 8)), '8');
    });

    test('10:00 anota 10, pero 9:59 ya anota 9', () {
      expect(TimeoutEngine.minuteMark(const Duration(minutes: 10)), '10');
      expect(TimeoutEngine.minuteMark(const Duration(seconds: 599)), '9');
    });

    test('por debajo del minuto se anota 1, no 0', () {
      // Un tiempo muerto pedido a falta de 20 segundos no puede figurar como
      // "minuto 0": eso es el final del período.
      expect(TimeoutEngine.minuteMark(const Duration(seconds: 20)), '1');
      expect(TimeoutEngine.minuteMark(const Duration(seconds: 59)), '1');
    });

    test('solo el reloj exactamente a cero anota 0', () {
      expect(TimeoutEngine.minuteMark(Duration.zero), '0');
    });
  });

  group('Reparto por tramos', () {
    test('cada período cae en su cupo', () {
      expect(TimeoutSlot.forPeriod(1), TimeoutSlot.firstHalf);
      expect(TimeoutSlot.forPeriod(2), TimeoutSlot.firstHalf);
      expect(TimeoutSlot.forPeriod(3), TimeoutSlot.secondHalf);
      expect(TimeoutSlot.forPeriod(4), TimeoutSlot.secondHalf);
      expect(TimeoutSlot.forPeriod(5), TimeoutSlot.overtime);
      expect(TimeoutSlot.forPeriod(9), TimeoutSlot.overtime);
    });
  });
}
