// lib/logic/catalog_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import 'package:myapp/features/catalog/domain/entities/catalog_models.dart' as model;
import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';
import 'package:myapp/core/di/providers.dart';

// `apiServiceProvider` vivía también aquí, duplicado: construía una SEGUNDA
// instancia de ApiService distinta de la del composition root. Ahora sale de
// core/di/providers.dart y se reexporta para no romper a quien lo importaba
// desde este archivo.
export 'package:myapp/core/di/providers.dart' show apiServiceProvider;

// FutureProvider que descarga los datos al iniciar la pantalla
final catalogProvider = FutureProvider.family<CatalogData, String>((ref,tournamentId) async {
  final api = ref.read(apiServiceProvider);
  return api.fetchCatalogs(tournamentId);
});

final tournamentDataByIdProvider = StreamProvider.family<model.CatalogData, String>((ref, tournamentId) async* {
  final db = ref.read(databaseProvider);
  
  // TRUCO: Escuchamos la tabla PLAYERS y TEAMS para que recargue si hay cambios.
  final stream = db.select(db.teams).watch(); 
  
  // Iniciamos con los datos actuales
  yield* stream.asyncMap((_) async {
    // 1. Equipos
    final teamsQuery = db.select(db.teams).join([
      innerJoin(db.tournamentTeams, db.tournamentTeams.teamId.equalsExp(db.teams.id))
    ]);
    teamsQuery.where(db.tournamentTeams.tournamentId.equals(tournamentId));
    final resultRows = await teamsQuery.get();
    
    final localTeams = resultRows.map((row) {
        final teamRow = row.readTable(db.teams);
        return model.Team(
            id: int.parse(teamRow.id), 
            name: teamRow.name, 
            shortName: teamRow.shortName ?? '', 
            coachName: teamRow.coachName ?? '',
            logoUrl: teamRow.logoUrl // <--- ¡AQUÍ ESTÁ LA MAGIA!
        );
    }).toList();

    // 2. Canchas
    final localVenues = await db.select(db.venues).get();

    // 3. Jugadores
    final localPlayers = await db.select(db.players).get();

    final officialsRows = await db.select(db.officials).get();
    final localOfficials = officialsRows.map((row) => model.Official(
      id: row.id, // Drift guarda ID como texto, lo pasamos a int
      name: row.name,
      role: row.role,
    )).toList();

    return model.CatalogData(
      tournaments: [],
      relationships: [], 
      venues: localVenues.map((v) => model.Venue(id: int.parse(v.id), name: v.name, address: v.address ?? '')).toList(),
      teams: localTeams,
      players: localPlayers.map((p) => model.Player(id: int.parse(p.id), teamId: p.teamId, name: p.name, defaultNumber: p.defaultNumber,photoUrl: p.photoUrl,)).toList(),
      officials: localOfficials,
    );
  });
});