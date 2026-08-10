// TempId: los identificadores que se generan sin conexión.
//
// Había tres estrategias distintas para lo mismo. Una de ellas truncaba los
// 5 primeros dígitos del timestamp, dejando 8 cifras en vez de 13: dos altas
// en el mismo milisegundo relativo producían el MISMO id y la segunda pisaba
// a la primera al insertar.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/utils/id_generator.dart';

void main() {
  group('TempId.nextNegative', () {
    test('es negativo: el signo marca "aún no está en la nube"', () {
      // No es decorativo. Por todo el código `id < 0` significa pendiente de
      // subir; un id positivo se trataría como real y se intentaría
      // actualizar en el backend, que devolvería 404.
      expect(TempId.nextNegative(), isNegative);
    });

    test('nunca repite, ni en llamadas consecutivas', () {
      // El caso que rompía: dar de alta varios jugadores seguidos entra en el
      // mismo milisegundo.
      final ids = List.generate(1000, (_) => TempId.nextNegative());
      expect(ids.toSet(), hasLength(1000));
    });

    test('conserva las 13 cifras del timestamp', () {
      // La variante truncada dejaba 8, reduciendo el margen contra colisiones
      // en cinco órdenes de magnitud.
      final id = TempId.nextNegative().abs();
      expect(id.toString().length, greaterThanOrEqualTo(13));
    });

    test('la versión en texto coincide con la numérica', () {
      final text = TempId.nextNegativeString();
      expect(int.parse(text), isNegative);
    });
  });

  group('TempId.newLocalMatchId', () {
    test('NO es negativo: no marca pendiente, solo identifica', () {
      // Un partido creado a mano necesita un id único y estable mientras dura
      // el alta; no es una entidad "por subir". Se mantiene aparte a
      // propósito.
      expect(int.parse(TempId.newLocalMatchId()), isPositive);
    });
  });
}
