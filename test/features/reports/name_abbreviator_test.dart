// Abreviatura de nombres largos en el acta.
//
// El caso que lo motivó: `PRUEBA ACTUALIZACIONFecha 11/08/2026` —el torneo
// invadiendo el campo de la fecha— y `Marcador: COBRAS 7 - 6 CLIPPERS NUEVA
// GENE`, cortado en seco. El acta se dibuja en coordenadas fijas, así que un
// nombre que no cabe no se recorta: se come la casilla de al lado.
//
// Aquí se mide en caracteres para que los casos se lean; en el PDF el
// predicado mide puntos con la Roboto real del documento.

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/reports/domain/name_abbreviator.dart';

void main() {
  /// Presupuesto en caracteres, que es lo legible en un test.
  String fit(String name, int maxChars) =>
      NameAbbreviator.fit(name, fits: (s) => s.length <= maxChars);

  group('lo que cabe no se toca', () {
    test('un nombre corto sale intacto', () {
      expect(fit('COBRAS', 20), 'COBRAS');
    });

    test('justo en el límite sale intacto', () {
      expect(fit('CLIPPERS', 8), 'CLIPPERS');
    });

    test('la cadena vacía no rompe', () {
      expect(fit('', 10), '');
    });

    test('los espacios de sobra se normalizan', () {
      expect(fit('  COBRAS   NEGRAS ', 20), 'COBRAS NEGRAS');
    });
  });

  group('escalera de abreviatura', () {
    test('primero se van los conectores', () {
      expect(fit('CLUB DEPORTIVO DE LA MONTAÑA', 24), 'CLUB DEPORTIVO MONTAÑA');
    });

    test('después se abrevia por el final', () {
      // Se conserva lo máximo posible: `GENERACION` cae antes que `NUEVA`.
      expect(fit('CLIPPERS NUEVA GENERACION', 20), 'CLIPPERS NUEVA G.');
    });

    test('si aún no cabe, cae la siguiente hacia atrás', () {
      expect(fit('CLIPPERS NUEVA GENERACION', 15), 'CLIPPERS N. G.');
    });

    test('el primer término nunca se abrevia', () {
      // Es el que identifica al equipo en el acta.
      expect(fit('CLIPPERS NUEVA GENERACION', 14), startsWith('CLIPPERS'));
    });

    test('una sola palabra kilométrica se recorta con punto', () {
      expect(fit('ACTUALIZACIONES', 8), 'ACTUALI.');
    });

    test('el recorte no deja dos puntos seguidos', () {
      expect(fit('CLIPPERS NUEVA GENERACION', 11), isNot(contains('..')));
    });

    test('un ancho absurdo devuelve algo, no una casilla en blanco', () {
      expect(fit('COBRAS', 0), isNotEmpty);
    });
  });

  group('lo que no debe hacer', () {
    test('no descarta un conector que abre el nombre', () {
      // Hay equipos que se llaman así.
      expect(fit('LOS ANGELES DE PUEBLA', 18), startsWith('LOS'));
    });

    test('el resultado siempre cabe', () {
      const nombres = [
        'CLIPPERS NUEVA GENERACION',
        'PRUEBA ACTUALIZACION',
        'CLUB DEPORTIVO DE LA MONTAÑA ALTA',
        'ACTUALIZACIONESINTERMINABLES',
        'A B C D E F G H I J K',
      ];
      for (final n in nombres) {
        for (var max = 1; max <= 30; max++) {
          expect(
            fit(n, max).length,
            lessThanOrEqualTo(max),
            reason: '«$n» con $max caracteres',
          );
        }
      }
    });

    test('es determinista: dos llamadas dan lo mismo', () {
      // El acta nombra al equipo en cuatro casillas; si variara, cada una
      // diría una cosa.
      expect(
        fit('CLIPPERS NUEVA GENERACION', 15),
        fit('CLIPPERS NUEVA GENERACION', 15),
      );
    });
  });
}
