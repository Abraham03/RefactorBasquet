/// Lógica de dominio pura (sin dependencias de Flutter): cuenta cuántas veces
/// se han enfrentado dos equipos dentro de un torneo.
///
/// Responsabilidad única (SRP): SOLO cuenta enfrentamientos. No sabe de UI,
/// ni de cómo se obtienen los datos (API, BD local, etc.). Cualquier fuente
/// que produzca pares de equipos alimenta el mismo constructor → DRY.
///
/// Es inmutable y testeable con puro Dart, sin levantar un widget.
class HeadToHeadCounter {
  /// Mapa: equipo -> (rival -> nº de veces enfrentados).
  final Map<int, Map<int, int>> _counts;

  const HeadToHeadCounter._(this._counts);

  /// Contador vacío (estado inicial / sin datos).
  const HeadToHeadCounter.empty() : _counts = const {};

  /// Construye el contador a partir de pares de IDs (idLocal, idVisitante).
  ///
  /// Ignora pares inválidos (0) o de un equipo contra sí mismo. Es la ÚNICA
  /// vía de construcción: tanto la API como la BD local mapean sus partidos a
  /// `(int, int)` y llaman aquí, evitando duplicar la lógica de conteo.
  factory HeadToHeadCounter.fromPairs(Iterable<(int, int)> pairs) {
    final counts = <int, Map<int, int>>{};
    for (final (a, b) in pairs) {
      if (a == 0 || b == 0 || a == b) continue;
      _bump(counts, a, b);
      _bump(counts, b, a);
    }
    return HeadToHeadCounter._(counts);
  }

  static void _bump(Map<int, Map<int, int>> m, int a, int b) {
    final row = m.putIfAbsent(a, () => <int, int>{});
    row[b] = (row[b] ?? 0) + 1;
  }

  /// Nº de veces que [a] y [b] ya se enfrentaron.
  ///
  /// [excludeA]/[excludeB]: descuenta un enfrentamiento concreto. Se usa al
  /// EDITAR un partido para no contar el partido que se está editando a sí mismo.
  int timesFaced(int? a, int? b, {int? excludeA, int? excludeB}) {
    if (a == null || b == null) return 0;
    var count = _counts[a]?[b] ?? 0;
    final bool esParOriginal = excludeA != null &&
        excludeB != null &&
        ((a == excludeA && b == excludeB) || (a == excludeB && b == excludeA));
    if (esParOriginal && count > 0) count -= 1;
    return count;
  }

  /// Azúcar sintáctico: ¿se han enfrentado al menos una vez?
  bool haveFaced(int? a, int? b, {int? excludeA, int? excludeB}) =>
      timesFaced(a, b, excludeA: excludeA, excludeB: excludeB) > 0;
}