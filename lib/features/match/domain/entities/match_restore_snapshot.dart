import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';

/// Todo lo necesario para reconstruir un partido ya jugado en el controller.
///
/// **Parameter Object.** `restoreFromDatabase` recibía estos 14 valores como
/// parámetros sueltos: dos pantallas los armaban por separado y cualquiera de
/// las dos podía olvidar uno o cruzar `teamAId` con `teamBId` sin que nada
/// fallara al compilar. Agrupados, se construyen una vez y viajan juntos.
class MatchRestoreSnapshot {
  /// Id de la fila `matches` (el acta), no del fixture.
  final String matchId;

  /// Id del partido en el calendario, si viene de ahí.
  final String? fixtureId;

  final List<CatalogPlayer> rosterA;
  final List<CatalogPlayer> rosterB;

  /// Titulares reales, leídos de `matchRosters`. Alimentan la "X" con círculo
  /// del acta en PDF.
  final Set<int> startersA;
  final Set<int> startersB;

  final int tournamentId;
  final int venueId;
  final int teamAId;
  final int teamBId;

  final String mainReferee;
  final String auxReferee;
  final String scorekeeper;

  const MatchRestoreSnapshot({
    required this.matchId,
    required this.rosterA,
    required this.rosterB,
    required this.startersA,
    required this.startersB,
    required this.tournamentId,
    required this.venueId,
    required this.teamAId,
    required this.teamBId,
    required this.mainReferee,
    required this.auxReferee,
    required this.scorekeeper,
    this.fixtureId,
  });
}
