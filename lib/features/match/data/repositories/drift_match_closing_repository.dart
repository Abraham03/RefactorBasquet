import 'package:drift/drift.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
import 'package:myapp/features/match/domain/repositories/match_closing_repository.dart';

/// Implementación sobre drift de [MatchClosingRepository].
class DriftMatchClosingRepository implements MatchClosingRepository {
  DriftMatchClosingRepository(this._db);

  final AppDatabase _db;

  @override
  Future<String> refereeLogoUrl(String tournamentId) async {
    final tournament =
        await (_db.select(_db.tournaments)
              ..where((t) => t.id.equals(tournamentId)))
            .getSingleOrNull();
    return tournament?.refereeLogoUrl ?? '';
  }

  @override
  Future<void> markFinished({
    required String matchId,
    String? fixtureId,
    required int scoreA,
    required int scoreB,
  }) async {
    // Las dos escrituras van juntas: un partido cerrado cuyo fixture siguiera
    // en SCHEDULED aparecería como pendiente en el calendario.
    await _db.transaction(() async {
      await (_db.update(_db.matches)..where((t) => t.id.equals(matchId))).write(
        const MatchesCompanion(status: Value(MatchStatus.finished)),
      );

      if (fixtureId == null || fixtureId.isEmpty) return;

      await (_db.update(
        _db.fixtures,
      )..where((t) => t.id.equals(fixtureId))).write(
        FixturesCompanion(
          status: const Value(MatchStatus.finished),
          scoreA: Value(scoreA),
          scoreB: Value(scoreB),
        ),
      );
    });
  }
}
