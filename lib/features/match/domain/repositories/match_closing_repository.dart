/// Lo que `MatchFinalizer` necesita de la base de datos para cerrar un partido.
///
/// **Por qué existe:** el finalizador vive en `domain/` y sostenía un
/// `AppDatabase`, haciendo consultas drift directas. El dominio son las reglas
/// del negocio: deben poder probarse sin base de datos y sobrevivir a un
/// cambio de motor de persistencia (regla 3 del plan).
///
/// Declara las **dos** operaciones que usa de verdad, no la base entera.
abstract interface class MatchClosingRepository {
  /// Logo del cuerpo arbitral, que vive en el torneo y se estampa en el acta.
  ///
  /// Devuelve cadena vacía si el torneo no existe o no tiene logo: el acta se
  /// genera igual, sin él.
  Future<String> refereeLogoUrl(String tournamentId);

  /// Marca el partido —y su entrada del calendario, si la tiene— como
  /// terminados, con el marcador final.
  ///
  /// El calendario se actualiza en la misma llamada porque un partido cerrado
  /// cuyo fixture siga en `SCHEDULED` aparecería como pendiente en la lista.
  Future<void> markFinished({
    required String matchId,
    String? fixtureId,
    required int scoreA,
    required int scoreB,
  });
}
