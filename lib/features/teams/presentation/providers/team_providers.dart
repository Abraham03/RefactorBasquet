import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/di/providers.dart';

/// Jugadores de un equipo, reactivo a la BD local.
///
/// Vivía al final de `team_detail_screen.dart`.
final teamPlayersStreamProvider =
    StreamProvider.family<List<Player>, int>((ref, teamId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.players)..where((p) => p.teamId.equals(teamId))).watch();
});
