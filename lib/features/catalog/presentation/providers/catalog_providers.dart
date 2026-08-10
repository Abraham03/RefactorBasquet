// lib/logic/catalog_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';
import 'package:myapp/core/di/providers.dart';
import 'package:myapp/core/network/result.dart';

// FutureProvider que descarga los datos al iniciar la pantalla
final catalogProvider = FutureProvider.family<CatalogData, String>((
  ref,
  tournamentId,
) async {
  final result = await ref.read(catalogApiProvider).fetchCatalogs(tournamentId);
  return switch (result) {
    Ok(:final value) => value,
    // Un FutureProvider comunica el fallo lanzando: así la UI puede usar
    // `AsyncValue.error` en vez de recibir una lista vacía indistinguible
    // de "no hay datos".
    Err(:final error) => throw error,
  };
});

final tournamentDataByIdProvider =
    StreamProvider.family<CatalogData, String>((
      ref,
      tournamentId,
    ) async* {
      final db = ref.read(databaseProvider);

      // TRUCO: Escuchamos la tabla PLAYERS y TEAMS para que recargue si hay cambios.
      final stream = db.select(db.teams).watch();

      // Iniciamos con los datos actuales
      yield* stream.asyncMap((_) async {
        // 1. Equipos
        final teamsQuery = db.select(db.teams).join([
          innerJoin(
            db.tournamentTeams,
            db.tournamentTeams.teamId.equalsExp(db.teams.id),
          ),
        ]);
        teamsQuery.where(db.tournamentTeams.tournamentId.equals(tournamentId));
        final resultRows = await teamsQuery.get();

        final localTeams = resultRows.map((row) {
          final teamRow = row.readTable(db.teams);
          return CatalogTeam(
            id: int.parse(teamRow.id),
            name: teamRow.name,
            shortName: teamRow.shortName ?? '',
            coachName: teamRow.coachName ?? '',
            logoUrl: teamRow.logoUrl, // <--- ¡AQUÍ ESTÁ LA MAGIA!
          );
        }).toList();

        // 2. Canchas
        final localVenues = await db.select(db.venues).get();

        // 3. Jugadores
        final localPlayers = await db.select(db.players).get();

        final officialsRows = await db.select(db.officials).get();
        final localOfficials = officialsRows
            .map(
              (row) => CatalogOfficial(
                id: row.id, // Drift guarda ID como texto, lo pasamos a int
                name: row.name,
                role: row.role,
              ),
            )
            .toList();

        return CatalogData(
          tournaments: [],
          relationships: [],
          venues: localVenues
              .map(
                (v) => CatalogVenue(
                  id: int.parse(v.id),
                  name: v.name,
                  address: v.address ?? '',
                ),
              )
              .toList(),
          teams: localTeams,
          players: localPlayers
              .map(
                (p) => CatalogPlayer(
                  id: int.parse(p.id),
                  teamId: p.teamId,
                  name: p.name,
                  defaultNumber: p.defaultNumber,
                  photoUrl: p.photoUrl,
                ),
              )
              .toList(),
          officials: localOfficials,
        );
      });
    });
