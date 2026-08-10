/// Identificadores generados en el dispositivo.
///
/// Había **tres** estrategias distintas conviviendo para lo mismo:
///   - `-DateTime.now().millisecondsSinceEpoch` (jugadores, equipos)
///   - `"-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}"`
///     (sedes y oficiales) — que **descarta los 5 primeros dígitos**, así que
///     el margen contra colisiones baja de 13 cifras a 8 y dos altas en el
///     mismo milisegundo relativo chocan.
///   - `DateTime.now().millisecondsSinceEpoch.toString()` en positivo, para el
///     id de un partido creado a mano.
///
/// Las dos primeras significan lo mismo y ahora son una sola. La tercera es
/// otra cosa y se mantiene aparte, con nombre propio.
library;

abstract final class TempId {
  /// Último valor entregado, para garantizar unicidad dentro del mismo
  /// milisegundo: dos altas seguidas iban a chocar.
  static int _last = 0;

  /// Id temporal para una entidad creada **sin conexión**.
  ///
  /// **El signo negativo es semántico, no decorativo:** por todo el código,
  /// `id < 0` significa "esto todavía no existe en la nube". Cambiarlo por un
  /// UUID rompería esa comprobación en repositorios, DAO y pantallas.
  static int nextNegative() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _last = now > _last ? now : _last + 1;
    return -_last;
  }

  /// Igual que [nextNegative] pero en texto, que es como lo guardan las
  /// tablas cuyo id es `TEXT`.
  static String nextNegativeString() => nextNegative().toString();

  /// Id **local** de un partido creado a mano, sin fixture asociado.
  ///
  /// No lleva signo negativo a propósito: no marca "pendiente de subir", solo
  /// necesita ser único y estable mientras dure la pantalla de alta.
  static String newLocalMatchId() =>
      DateTime.now().millisecondsSinceEpoch.toString();
}
