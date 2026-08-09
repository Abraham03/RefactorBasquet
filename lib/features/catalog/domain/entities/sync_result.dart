/// Resultado de una operación de subida a la nube.
///
/// El repositorio NO muestra feedback (no conoce la UI). Devuelve este
/// objeto inmutable y la pantalla decide cómo presentarlo. Así la capa
/// de datos queda independiente de Flutter: testeable y reutilizable.
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

  /// True si se subió algo de fixtures/partidos y conviene re-descargar.
  bool get needsRedownload => fixtures > 0 || matches > 0;

  bool get hasSkipped => skippedMatches.isNotEmpty;

  String toSummary() =>
      "Subidos: $tournaments Torneos, $teams Equipos, $matches Partidos, "
      "$players Jugadores, $fixtures Calendarios, $officials Oficiales, "
      "$venues Canchas.";

  /// Permite ir acumulando resultados parciales por entidad (Fase 2).
  SyncResult copyWith({
    int? tournaments,
    int? venues,
    int? teams,
    int? players,
    int? fixtures,
    int? matches,
    int? officials,
    List<String>? skippedMatches,
  }) {
    return SyncResult(
      tournaments: tournaments ?? this.tournaments,
      venues: venues ?? this.venues,
      teams: teams ?? this.teams,
      players: players ?? this.players,
      fixtures: fixtures ?? this.fixtures,
      matches: matches ?? this.matches,
      officials: officials ?? this.officials,
      skippedMatches: skippedMatches ?? this.skippedMatches,
    );
  }
}