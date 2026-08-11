// El reloj guardado: formato y parseo.
//
// Se escribe al persistir el partido y en cada evento, y se vuelve a leer al
// reanudar uno interrumpido. Las dos mitades estaban escritas a mano en sitios
// distintos: nada garantizaba que encajaran, y si se desincronizan un partido
// a medias se reanuda con el reloj equivocado.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/match/domain/engines/match_clock_format.dart';

void main() {
  group('Formato', () {
    test('rellena los segundos con cero, los minutos no', () {
      // Así se venía guardando: "9:05", no "09:05".
      expect(
        MatchClockFormat.format(const Duration(minutes: 9, seconds: 5)),
        '9:05',
      );
      expect(MatchClockFormat.format(const Duration(minutes: 10)), '10:00');
    });

    test('por debajo del minuto', () {
      expect(MatchClockFormat.format(const Duration(seconds: 7)), '0:07');
      expect(MatchClockFormat.format(Duration.zero), '0:00');
    });

    test('un tiempo negativo no produce basura', () {
      // El reloj no debería bajar de cero, pero si lo hace es preferible
      // guardar "0:00" a escribir "-1:-1" en la base de datos.
      expect(MatchClockFormat.format(const Duration(seconds: -5)), '0:00');
    });
  });

  group('Parseo', () {
    test('lee lo que escribe el formateador', () {
      for (final d in [
        const Duration(minutes: 10),
        const Duration(minutes: 4, seconds: 59),
        const Duration(seconds: 7),
        Duration.zero,
      ]) {
        expect(
          MatchClockFormat.parse(MatchClockFormat.format(d)),
          d,
          reason: 'ida y vuelta de $d',
        );
      }
    });

    test('acepta minutos con cero a la izquierda', () {
      // Los eventos se guardaban con relleno ("04:59"): hay partidos ya
      // grabados así y tienen que seguir leyéndose.
      expect(
        MatchClockFormat.parse('04:59'),
        const Duration(minutes: 4, seconds: 59),
      );
    });

    test('tolera espacios alrededor', () {
      expect(
        MatchClockFormat.parse(' 4 : 59 '),
        const Duration(minutes: 4, seconds: 59),
      );
    });
  });

  group('Datos que no sirven', () {
    test('nulo, vacío o sin dos puntos devuelve el valor por defecto', () {
      // Diez minutos, no cero: ante la duda es preferible dar tiempo de más y
      // que el anotador lo ajuste, a arrancar en cero y dar el período por
      // terminado.
      for (final raw in [null, '', 'sin dos puntos', '900']) {
        expect(
          MatchClockFormat.parse(raw),
          MatchClockFormat.fallback,
          reason: 'para ${raw ?? "null"}',
        );
      }
    });

    test('minutos ilegibles usan el valor por defecto', () {
      expect(MatchClockFormat.parse('abc:30'), MatchClockFormat.fallback);
    });

    test('segundos ilegibles valen 0, pero el minuto se conserva', () {
      // El minuto ya lleva la información útil: perderlo entero por unos
      // segundos corruptos sería peor.
      expect(MatchClockFormat.parse('7:xx'), const Duration(minutes: 7));
    });
  });
}
