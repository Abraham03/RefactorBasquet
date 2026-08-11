// El contrato que sacó a `MatchFinalizer` de drift.
//
// Lo que se prueba aquí no es «drift escribe», es la regla que justifica que
// las dos escrituras vivan en un mismo método: partido y calendario se cierran
// juntos o no se cierra ninguno.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/features/match/data/repositories/drift_match_closing_repository.dart';
import 'package:myapp/core/constants/match_status.dart';

void main() {
  late AppDatabase db;
  late DriftMatchClosingRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftMatchClosingRepository(db);

    await db
        .into(db.matches)
        .insert(
          MatchesCompanion.insert(
            id: const Value('M1'),
            teamAName: 'Lobos',
            teamBName: 'Pumas',
            fixtureId: const Value('F9'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> insertFixture() => db
      .into(db.fixtures)
      .insert(
        FixturesCompanion.insert(
          id: 'F9',
          tournamentId: '7',
          roundName: 'Jornada 1',
          teamAId: '3',
          teamBId: '4',
          teamAName: 'Lobos',
          teamBName: 'Pumas',
          status: const Value(MatchStatus.scheduled),
        ),
      );

  Future<String?> matchStatus() async => (await (db.select(
    db.matches,
  )..where((t) => t.id.equals('M1'))).getSingle()).status;

  group('refereeLogoUrl', () {
    test('devuelve el logo del torneo', () async {
      await db
          .into(db.tournaments)
          .insert(
            TournamentsCompanion.insert(
              id: const Value('7'),
              name: 'Liga',
              refereeLogoUrl: const Value('https://x/arbitros.png'),
            ),
          );

      expect(await repo.refereeLogoUrl('7'), 'https://x/arbitros.png');
    });

    test('devuelve cadena vacía si el torneo no existe', () async {
      // El acta se genera igual, sin logo. Si esto lanzara, un torneo borrado
      // impediría cerrar el partido con el árbitro delante.
      expect(await repo.refereeLogoUrl('999'), '');
    });
  });

  group('markFinished', () {
    test('cierra el partido y su entrada del calendario', () async {
      await insertFixture();

      await repo.markFinished(
        matchId: 'M1',
        fixtureId: 'F9',
        scoreA: 78,
        scoreB: 65,
      );

      expect(await matchStatus(), MatchStatus.finished);

      final fixture = await (db.select(
        db.fixtures,
      )..where((t) => t.id.equals('F9'))).getSingle();
      expect(fixture.status, MatchStatus.finished);
      expect(fixture.scoreA, 78);
      expect(fixture.scoreB, 65);
    });

    test('un partido sin fixture se cierra igual', () async {
      // Los amistosos se crean sin calendario.
      await repo.markFinished(matchId: 'M1', scoreA: 50, scoreB: 49);

      expect(await matchStatus(), MatchStatus.finished);
    });

    test('fixtureId vacío se trata como ausente, no como id ""', () async {
      await repo.markFinished(
        matchId: 'M1',
        fixtureId: '',
        scoreA: 50,
        scoreB: 49,
      );

      expect(await matchStatus(), MatchStatus.finished);
    });

    test('si el calendario falla, el partido NO queda cerrado', () async {
      // La razón de ser de la transacción: un partido en FINISHED cuyo fixture
      // siguiera en SCHEDULED aparecería como pendiente en el calendario, y
      // el árbitro volvería a abrirlo.
      //
      // Apuntar a un fixture inexistente no sirve para provocar el fallo: un
      // UPDATE que no toca filas no es un error. Se fuerza con un trigger que
      // aborta, y que salta DESPUÉS de que la fila del partido ya se escribió
      // —si no hubiera transacción, ese FINISHED quedaría grabado.
      await insertFixture();
      await db.customStatement(
        'CREATE TRIGGER no_fixture_update BEFORE UPDATE ON fixtures '
        "BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );

      await expectLater(
        repo.markFinished(
          matchId: 'M1',
          fixtureId: 'F9',
          scoreA: 78,
          scoreB: 65,
        ),
        throwsA(anything),
      );

      expect(
        await matchStatus(),
        isNot(MatchStatus.finished),
        reason: 'la escritura del partido debió revertirse con el rollback',
      );
    });
  });
}
