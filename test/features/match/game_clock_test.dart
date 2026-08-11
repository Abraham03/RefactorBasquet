// El reloj de juego: reglas y temporizador.
//
// Las reglas vivían dentro del callback de `Timer.periodic` en el controller,
// así que probarlas exigía esperar segundos reales. Nadie lo hizo.
//
// Ahora se separan en dos: las decisiones son puras y el temporizador es un
// envoltorio fino que `fake_async` puede acelerar. Es el primer uso de
// `fake_async`, que se añadió en la Fase 0 precisamente para esto.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/match/domain/engines/game_clock.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';

MatchState stateAt(
  Duration timeLeft, {
  int period = 1,
  List<String> timeoutsA = const [],
  List<String> timeoutsB = const [],
}) {
  return MatchState(
    matchId: 'M1',
    timeLeft: timeLeft,
    currentPeriod: period,
    teamATimeouts2: timeoutsA,
    teamBTimeouts2: timeoutsB,
  );
}

void main() {
  group('Avance del reloj', () {
    test('descuenta un segundo', () {
      final tick = GameClockRules.advance(stateAt(const Duration(minutes: 10)));

      expect(tick.timeLeft, const Duration(seconds: 599));
      expect(tick.expired, isFalse);
    });

    test('a cero el período se da por terminado', () {
      final tick = GameClockRules.advance(stateAt(Duration.zero));

      expect(tick.expired, isTrue);
      expect(tick.timeLeft, Duration.zero);
      expect(
        tick.shouldPersist,
        isTrue,
        reason: 'el final de período se guarda aunque no toque por cadencia',
      );
    });
  });

  group('Cadencia de guardado', () {
    test('se persiste cada 5 segundos, no en cada tick', () {
      // Escribir en la base de datos una vez por segundo durante 40 minutos
      // de partido son 2400 escrituras innecesarias.
      final persisted = <int>[];
      for (var s = 600; s > 590; s--) {
        final tick = GameClockRules.advance(stateAt(Duration(seconds: s)));
        if (tick.shouldPersist) persisted.add(tick.timeLeft.inSeconds);
      }

      expect(persisted, [595, 590]);
    });
  });

  group('Quema automática de tiempos muertos (clutch time)', () {
    test('salta al cruzar 2:00 del último período', () {
      final tick = GameClockRules.advance(
        stateAt(const Duration(seconds: 121), period: 4),
      );

      expect(tick.shouldAutoBurn, isTrue);
    });

    test('NO salta en períodos anteriores', () {
      for (final period in [1, 2, 3]) {
        final tick = GameClockRules.advance(
          stateAt(const Duration(seconds: 121), period: period),
        );
        expect(tick.shouldAutoBurn, isFalse, reason: 'período $period');
      }
    });

    test('salta UNA sola vez, no en cada segundo por debajo de 2:00', () {
      // Se compara por igualdad y no por "menor que": si no, cada tick del
      // último minuto volvería a quemar tiempos muertos.
      final burns = <int>[];
      for (var s = 125; s > 110; s--) {
        final tick = GameClockRules.advance(
          stateAt(Duration(seconds: s), period: 4),
        );
        if (tick.shouldAutoBurn) burns.add(s);
      }

      expect(burns, hasLength(1));
    });

    test('quema uno a cada equipo que no haya gastado ninguno', () {
      final burned = GameClockRules.applyAutoBurn(stateAt(Duration.zero))!;

      expect(burned.teamATimeouts2, ['X']);
      expect(burned.teamBTimeouts2, ['X']);
    });

    test('al equipo que ya gastó uno no se le quema nada', () {
      final burned = GameClockRules.applyAutoBurn(
        stateAt(Duration.zero, timeoutsA: const ['1']),
      )!;

      expect(burned.teamATimeouts2, ['1'], reason: 'se respeta el suyo');
      expect(burned.teamBTimeouts2, ['X']);
    });

    test('si ambos ya gastaron, devuelve null', () {
      // `null` evita meter en el historial de deshacer un paso que no cambió
      // nada: el usuario tendría que pulsar deshacer dos veces.
      final burned = GameClockRules.applyAutoBurn(
        stateAt(Duration.zero, timeoutsA: const ['1'], timeoutsB: const ['2']),
      );

      expect(burned, isNull);
    });
  });

  group('GameClock — el temporizador', () {
    test('llama al callback una vez por intervalo', () {
      fakeAsync((async) {
        var ticks = 0;
        final clock = GameClock()..start(() => ticks++);

        async.elapse(const Duration(seconds: 3));
        expect(ticks, 3);

        clock.dispose();
      });
    });

    test('stop detiene los ticks', () {
      fakeAsync((async) {
        var ticks = 0;
        final clock = GameClock()..start(() => ticks++);

        async.elapse(const Duration(seconds: 2));
        clock.stop();
        async.elapse(const Duration(seconds: 5));

        expect(ticks, 2, reason: 'no sigue corriendo tras pararlo');
        expect(clock.isRunning, isFalse);
      });
    });

    test('arrancarlo dos veces no deja dos temporizadores corriendo', () {
      // Sin el `cancel` previo, cada pulsación de play sumaría un temporizador
      // y el reloj bajaría al doble de velocidad.
      fakeAsync((async) {
        var ticks = 0;
        final clock = GameClock()
          ..start(() => ticks++)
          ..start(() => ticks++);

        async.elapse(const Duration(seconds: 3));

        expect(ticks, 3);
        clock.dispose();
      });
    });

    test('dispose deja de disparar', () {
      fakeAsync((async) {
        var ticks = 0;
        GameClock()
          ..start(() => ticks++)
          ..dispose();

        async.elapse(const Duration(seconds: 5));
        expect(ticks, 0);
      });
    });
  });

  group('Quema al cerrar el partido', () {
    // `burnUnusedAtEnd` NO mira el reloj, y esa es toda la diferencia con
    // `autoBurnAlreadyHappened`. Al cerrar, el equipo que no gastó su tiempo
    // muerto de la segunda mitad lo ha perdido igual: ya no hay ocasión de
    // pedirlo. Importa porque el reloj guardado no siempre llega a 00:00
    // —`setTime` no persiste y `setPeriod` reinicia a 10:00— y el acta salía
    // sin la marca.

    test('con el reloj intacto, un partido cerrado en el 4o SÍ quema', () {
      const state = MatchState(
        currentPeriod: 4,
        timeLeft: Duration(minutes: 10),
      );

      expect(GameClockRules.autoBurnAlreadyHappened(state), isFalse);
      final burned = GameClockRules.burnUnusedAtEnd(state);
      expect(burned, isNotNull);
      expect(burned!.teamATimeouts2, contains('X'));
      expect(burned.teamBTimeouts2, contains('X'));
    });

    test('en prórroga también', () {
      const state = MatchState(
        currentPeriod: 5,
        timeLeft: Duration(minutes: 5),
      );

      expect(
        GameClockRules.burnUnusedAtEnd(state)!.teamATimeouts2,
        contains('X'),
      );
    });

    test('un partido cerrado antes del 4o no quema nada', () {
      // Inasistencia declarada en el 2o: no hubo segunda mitad que jugar.
      const state = MatchState(
        currentPeriod: 2,
        timeLeft: Duration(minutes: 3),
      );

      expect(GameClockRules.burnUnusedAtEnd(state), isNull);
    });

    test('no toca al equipo que sí gastó el suyo', () {
      const state = MatchState(
        currentPeriod: 4,
        timeLeft: Duration(minutes: 10),
        teamATimeouts2: ['7'],
      );

      final burned = GameClockRules.burnUnusedAtEnd(state)!;
      expect(burned.teamATimeouts2, ['7']);
      expect(burned.teamBTimeouts2, contains('X'));
    });

    test('devuelve null si los dos ya gastaron: nada que quemar', () {
      const state = MatchState(
        currentPeriod: 4,
        timeLeft: Duration(minutes: 10),
        teamATimeouts2: ['7'],
        teamBTimeouts2: ['5'],
      );

      expect(GameClockRules.burnUnusedAtEnd(state), isNull);
    });
  });
}
