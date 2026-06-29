/// Resultado de una operación de subida a la nube.
///
/// El repositorio NO muestra feedback (no conoce la UI). Devuelve este
/// objeto y la pantalla decide cómo presentarlo. Esto mantiene la capa
/// de datos independiente de Flutter (testeable, reutilizable).
class SyncResult {
  final int tournaments;
  final int venues;
  final int teams;
  final int players;
  final int fixtures;
  final int matches;
  final int officials;

  /// Partidos omitidos por contener jugadores offline sin sincronizar.
  final List<String> skippedMatches;

  /// True si algo de fixtures/partidos se subió y conviene re-descargar.
  bool get needsRedownload => fixtures > 0 || matches > 0;

  bool get hasSkipped => skippedMatches.isNotEmpty;

  const SyncResult({
    this.tournaments = 0,
    this.venues = 0,
    this.teams = 0,
    this.players = 0,
    this.fixtures = 0,
    this.matches = 0,
    this.officials = 0,
    this.skippedMatches = const [],
  });

  String toSummary() =>
      "Subidos: $tournaments Torneos, $teams Equipos, $matches Partidos, "
      "$players Jugadores, $fixtures Calendarios, $officials Oficiales, "
      "$venues Canchas.";
}