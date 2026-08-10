/// Entidades del catálogo tal y como las devuelve el backend.
///
/// **Por qué el prefijo `Catalog`:** drift genera una clase por tabla con el
/// nombre en singular (`Team`, `Player`, `Tournament`, `Venue`, `Official`),
/// así que estos modelos colisionaban con las cinco. La única salida era
/// importar con alias (`as catalog`, `as model`, `as models`), y un mismo
/// archivo llegaba a importar el mismo fichero dos veces, con y sin alias.
/// Peor: `Team` significaba una cosa u otra según el import de cada archivo.
///
/// Estos son los modelos de RED (lo que viaja por JSON). Los de drift son los
/// de PERSISTENCIA. Que se llamen distinto no es cosmética: son cosas
/// distintas con campos distintos.
library;

import 'package:myapp/core/utils/json_parsing.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_download.dart';

class CatalogTournament {
  final int id;
  final String name;
  final String category;
  final String? status;
  final String? logoUrl;
  final String? refereeLogoUrl;

  const CatalogTournament({
    required this.id,
    required this.name,
    required this.category,
    this.status,
    this.logoUrl,
    this.refereeLogoUrl,
  });

  factory CatalogTournament.fromJson(Map<String, dynamic> json) {
    return CatalogTournament(
      id: parseId(json['id']),
      name: json['name'] as String,
      category: json['category'] as String? ?? '',
      status: json['status'] as String?,
      logoUrl: json['logo_url'] as String?,
      refereeLogoUrl: json['url_arbitro'] as String?,
    );
  }

  /// Las claves son el contrato con el backend (invariante I2 del plan).
  /// El test de ida y vuelta las fija: renombrar una aquí rompe el test.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'status': status,
    'logo_url': logoUrl,
    'url_arbitro': refereeLogoUrl,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogTournament &&
          other.id == id &&
          other.name == name &&
          other.category == category &&
          other.status == status &&
          other.logoUrl == logoUrl &&
          other.refereeLogoUrl == refereeLogoUrl;

  @override
  int get hashCode =>
      Object.hash(id, name, category, status, logoUrl, refereeLogoUrl);
}

class TournamentTeamRelation {
  final int tournamentId;
  final int teamId;

  const TournamentTeamRelation({
    required this.tournamentId,
    required this.teamId,
  });

  factory TournamentTeamRelation.fromJson(Map<String, dynamic> json) {
    return TournamentTeamRelation(
      tournamentId: parseId(json['tournament_id']),
      teamId: parseId(json['team_id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'tournament_id': tournamentId,
    'team_id': teamId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentTeamRelation &&
          other.tournamentId == tournamentId &&
          other.teamId == teamId;

  @override
  int get hashCode => Object.hash(tournamentId, teamId);
}

class CatalogVenue {
  final int id;
  final String name;
  final String address;

  const CatalogVenue({
    required this.id,
    required this.name,
    required this.address,
  });

  factory CatalogVenue.fromJson(Map<String, dynamic> json) {
    return CatalogVenue(
      id: parseId(json['id']),
      name: json['name'] as String,
      address: json['address'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'address': address};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogVenue &&
          other.id == id &&
          other.name == name &&
          other.address == address;

  @override
  int get hashCode => Object.hash(id, name, address);
}

class CatalogTeam {
  final int id;
  final String name;
  final String shortName;
  final String coachName;
  final String? logoUrl;

  const CatalogTeam({
    required this.id,
    required this.name,
    required this.shortName,
    required this.coachName,
    this.logoUrl,
  });

  factory CatalogTeam.fromJson(Map<String, dynamic> json) {
    return CatalogTeam(
      id: parseId(json['id']),
      name: json['name'] as String,
      shortName: json['short_name'] as String? ?? '',
      coachName: json['coach_name'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'short_name': shortName,
    'coach_name': coachName,
    'logo_url': logoUrl,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogTeam &&
          other.id == id &&
          other.name == name &&
          other.shortName == shortName &&
          other.coachName == coachName &&
          other.logoUrl == logoUrl;

  @override
  int get hashCode => Object.hash(id, name, shortName, coachName, logoUrl);
}

class CatalogPlayer {
  final int id;
  final int teamId;
  final String name;
  final int defaultNumber;
  final String? photoUrl;

  const CatalogPlayer({
    required this.id,
    required this.teamId,
    required this.name,
    required this.defaultNumber,
    this.photoUrl,
  });

  factory CatalogPlayer.fromJson(Map<String, dynamic> json) {
    return CatalogPlayer(
      id: parseId(json['id']),
      teamId: parseId(json['team_id']),
      // El dorsal SÍ admite ausencia: un jugador puede no tenerlo asignado.
      defaultNumber: tryParseId(json['default_number']) ?? 0,
      name: json['name'] as String,
      photoUrl: json['photo_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'team_id': teamId,
    'name': name,
    'default_number': defaultNumber,
    'photo_url': photoUrl,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogPlayer &&
          other.id == id &&
          other.teamId == teamId &&
          other.name == name &&
          other.defaultNumber == defaultNumber &&
          other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(id, teamId, name, defaultNumber, photoUrl);
}

class CatalogOfficial {
  /// Es `String` y no `int` a propósito: los oficiales creados sin conexión
  /// llevan un id temporal negativo generado en el dispositivo.
  final String id;
  final String name;
  final String role;
  final String? signature;

  const CatalogOfficial({
    required this.id,
    required this.name,
    required this.role,
    this.signature,
  });

  factory CatalogOfficial.fromJson(Map<String, dynamic> json) {
    return CatalogOfficial(
      id: json['id'].toString(),
      name: json['name'] as String,
      role: json['role'] as String? ?? 'REFEREE',
      // El backend usa las dos claves según el endpoint.
      signature: (json['signature_data'] ?? json['signature']) as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'signature_data': signature,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogOfficial &&
          other.id == id &&
          other.name == name &&
          other.role == role &&
          other.signature == signature;

  @override
  int get hashCode => Object.hash(id, name, role, signature);
}

/// Contenedor para recibir todo el catálogo de golpe.
class CatalogData {
  final List<CatalogTournament> tournaments;
  final List<CatalogVenue> venues;
  final List<CatalogTeam> teams;
  final List<CatalogPlayer> players;
  final List<TournamentTeamRelation> relationships;
  final List<CatalogOfficial> officials;

  /// Calendario y rosters finalizados. Eran `List<dynamic>` y su JSON crudo
  /// llegaba hasta la UI; ahora se parsean aquí (Fase 5).
  final List<CatalogFixture> fixtures;
  final List<CatalogRoster> finishedRosters;

  const CatalogData({
    required this.tournaments,
    required this.venues,
    required this.teams,
    required this.players,
    required this.relationships,
    required this.officials,
    this.fixtures = const [],
    this.finishedRosters = const [],
  });
}
