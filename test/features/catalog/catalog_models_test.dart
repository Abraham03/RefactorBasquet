// Los modelos de catálogo: parseo, igualdad y contrato de claves.
//
// El test de ida y vuelta no es ceremonia: **fija los nombres de las claves
// JSON**, que son el contrato con el backend PHP (invariante I2 del plan).
// Renombrar `short_name` a `shortName` en un `fromJson` compilaría
// perfectamente y rompería la app contra el servidor; aquí se cae.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';

void main() {
  group('Ida y vuelta: fromJson(toJson(x)) == x', () {
    test('CatalogTournament', () {
      const original = CatalogTournament(
        id: 7,
        name: 'Liga 2026',
        category: 'VARONIL',
        status: 'ACTIVE',
        logoUrl: 'https://x/logo.png',
        refereeLogoUrl: 'https://x/ref.png',
      );
      expect(CatalogTournament.fromJson(original.toJson()), original);
    });

    test('CatalogVenue', () {
      const original = CatalogVenue(
        id: 5,
        name: 'Gimnasio Municipal',
        address: 'Av. Reforma 742',
      );
      expect(CatalogVenue.fromJson(original.toJson()), original);
    });

    test('CatalogTeam', () {
      const original = CatalogTeam(
        id: 3,
        name: 'Lobos',
        shortName: 'LOB',
        coachName: 'Coach Ruiz',
        logoUrl: 'https://x/lobos.png',
      );
      expect(CatalogTeam.fromJson(original.toJson()), original);
    });

    test('CatalogPlayer', () {
      const original = CatalogPlayer(
        id: 9,
        teamId: 3,
        name: 'Pedro Gómez',
        defaultNumber: 12,
        photoUrl: 'https://x/9.png',
      );
      expect(CatalogPlayer.fromJson(original.toJson()), original);
    });

    test('CatalogOfficial', () {
      const original = CatalogOfficial(
        id: '7',
        name: 'Juan Pérez',
        role: 'ARBITRO_PRINCIPAL',
        signature: 'iVBORw0KGgo=',
      );
      expect(CatalogOfficial.fromJson(original.toJson()), original);
    });

    test('TournamentTeamRelation', () {
      const original = TournamentTeamRelation(tournamentId: 1, teamId: 2);
      expect(TournamentTeamRelation.fromJson(original.toJson()), original);
    });
  });

  group('Claves del backend (contrato I2)', () {
    test('las claves son snake_case, no los nombres Dart', () {
      const team = CatalogTeam(
        id: 3,
        name: 'Lobos',
        shortName: 'LOB',
        coachName: 'Coach Ruiz',
      );
      expect(
        team.toJson().keys,
        containsAll(<String>['short_name', 'coach_name', 'logo_url']),
      );

      const tournament = CatalogTournament(id: 1, name: 'L', category: 'V');
      // `url_arbitro` está en español en el backend: no "corregirlo".
      expect(tournament.toJson().keys, contains('url_arbitro'));

      const player = CatalogPlayer(
        id: 1,
        teamId: 2,
        name: 'P',
        defaultNumber: 4,
      );
      expect(
        player.toJson().keys,
        containsAll(<String>['team_id', 'default_number', 'photo_url']),
      );
    });
  });

  group('Coerción del JSON de PHP', () {
    test('los ids llegan como string y se parsean a int', () {
      // MySQL vía PHP serializa los enteros como texto. Antes esto se resolvía
      // con `int.parse(json['id'].toString())` repetido ~12 veces.
      final team = CatalogTeam.fromJson(const {
        'id': '3',
        'name': 'Lobos',
        'short_name': 'LOB',
        'coach_name': 'Coach Ruiz',
      });
      expect(team.id, 3);
    });

    test('los campos opcionales ausentes toman su defecto', () {
      final team = CatalogTeam.fromJson(const {'id': 3, 'name': 'Lobos'});
      expect(team.shortName, '');
      expect(team.coachName, '');
      expect(team.logoUrl, isNull);
    });

    test('un dorsal ausente vale 0, no revienta', () {
      // A diferencia del id, el dorsal SÍ admite ausencia.
      final player = CatalogPlayer.fromJson(const {
        'id': 9,
        'team_id': 3,
        'name': 'Pedro',
      });
      expect(player.defaultNumber, 0);
    });

    test('un id ausente falla en voz alta', () {
      // Un id nulo que se colara silenciosamente acabaría escrito en la BD.
      expect(
        () => CatalogTeam.fromJson(const {'name': 'Lobos'}),
        throwsFormatException,
      );
    });

    test('la firma del oficial acepta las dos claves del backend', () {
      expect(
        CatalogOfficial.fromJson(const {
          'id': 1,
          'name': 'Juan',
          'signature_data': 'AAA',
        }).signature,
        'AAA',
      );
      expect(
        CatalogOfficial.fromJson(const {
          'id': 1,
          'name': 'Juan',
          'signature': 'BBB',
        }).signature,
        'BBB',
      );
    });

    test('el rol por defecto es REFEREE', () {
      final official = CatalogOfficial.fromJson(const {
        'id': 1,
        'name': 'Juan',
      });
      expect(official.role, 'REFEREE');
    });
  });

  group('Igualdad estructural', () {
    test('dos instancias con los mismos campos son iguales', () {
      // Sin `==`, Riverpod reemite y la UI se reconstruye aunque los datos no
      // hayan cambiado.
      const a = CatalogVenue(id: 1, name: 'Gim', address: 'Calle 1');
      const b = CatalogVenue(id: 1, name: 'Gim', address: 'Calle 1');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // El set se llena en tiempo de ejecución: escrito como literal, el
      // analizador detecta el duplicado y avisa antes de compilar.
      expect(<CatalogVenue>{}..addAll([a, b]), hasLength(1));
    });

    test('un campo distinto las hace distintas', () {
      const a = CatalogVenue(id: 1, name: 'Gim', address: 'Calle 1');
      const b = CatalogVenue(id: 1, name: 'Gim', address: 'Calle 2');
      expect(a, isNot(b));
    });
  });
}
