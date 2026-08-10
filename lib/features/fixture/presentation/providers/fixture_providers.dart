import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/di/providers.dart';

/// Fixture local de un torneo, agrupado por jornada.
///
/// Vivía dentro de `fixture_list_screen.dart`. Un provider declarado en un
/// archivo de pantalla no se puede reutilizar ni sustituir en un test sin
/// arrastrar el widget entero.
final localFixtureProvider =
    StreamProvider.family<Map<String, List<Fixture>>, String>((
  ref,
  tournamentId,
) {
  final db = ref.watch(databaseProvider);

  return (db.select(db.fixtures)
        ..where((tbl) => tbl.tournamentId.equals(tournamentId)))
      .watch()
      .map((matches) {
    final grouped = <String, List<Fixture>>{};
    for (final m in matches) {
      grouped.putIfAbsent(m.roundName, () => []).add(m);
    }
    return grouped;
  });
});
