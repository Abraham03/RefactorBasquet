/// Roster de un partido con el nombre del jugador ya resuelto.
///
/// Es la **proyección de una consulta** (roster ⨝ players), no una entidad de
/// catálogo: por eso vive junto al DAO que la produce y no en
/// `features/catalog/domain/`. Tenerla allí obligaba a `matches_dao` —que es
/// infraestructura de `core/`— a importar `features/`, violando la regla 2 del
/// plan.
class RosterWithName {
  final String playerId;
  final String name;
  final int jerseyNumber;
  final String teamSide;
  final bool attended;

  const RosterWithName({
    required this.playerId,
    required this.name,
    required this.jerseyNumber,
    required this.teamSide,
    required this.attended,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RosterWithName &&
          other.playerId == playerId &&
          other.name == name &&
          other.jerseyNumber == jerseyNumber &&
          other.teamSide == teamSide &&
          other.attended == attended;

  @override
  int get hashCode =>
      Object.hash(playerId, name, jerseyNumber, teamSide, attended);
}
