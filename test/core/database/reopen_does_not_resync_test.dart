// Regresión de campo: al subir un partido jugado offline, la sincronización
// se llevó también dos partidos anteriores que YA estaban en la nube, y les
// volvió a mandar el PDF.
//
// La causa no estaba en la subida —que hace lo correcto: mandar todo lo que
// tenga `isSynced == false`— sino en que reabrir un acta finalizada la
// devolvía a la cola de pendientes.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/constants/match_status.dart';
import 'package:myapp/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.matches)
        .insert(
          MatchesCompanion.insert(
            id: const Value('M1'),
            teamAName: 'Lobos',
            teamBName: 'Pumas',
            status: const Value(MatchStatus.finished),
            isSynced: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  Future<bool> isSynced() async => (await (db.select(
    db.matches,
  )..where((t) => t.id.equals('M1'))).getSingle()).isSynced;

  test('reabrir un acta ya subida NO la devuelve a la cola', () async {
    // `markInProgress: false` es la señal de "estoy reabriendo un partido
    // FINALIZADO". El método ya cuidaba de no revertir el estado del
    // calendario, pero escribía `isSynced: false` sin condición, y la
    // siguiente sincronización volvía a mandar el acta entera, PDF incluido.
    await db.matchesDao.updateMatchMetadata(
      'M1',
      null,
      3,
      4,
      'Juan',
      'Ana',
      'Luis',
      markInProgress: false,
    );

    expect(await isSynced(), isTrue);
  });

  test('iniciar un partido SÍ lo marca pendiente de subir', () async {
    // El otro lado de la moneda: un partido que empieza tiene cambios que
    // subir, y si esto dejara de marcarlo, no se subiría nunca.
    await db.matchesDao.updateMatchMetadata(
      'M1',
      null,
      3,
      4,
      'Juan',
      'Ana',
      'Luis',
    );

    expect(await isSynced(), isFalse);
  });

  test('los metadatos se escriben en los dos casos', () async {
    await db.matchesDao.updateMatchMetadata(
      'M1',
      null,
      3,
      4,
      'Pedro',
      'Ana',
      'Luis',
      markInProgress: false,
    );

    final row = await (db.select(
      db.matches,
    )..where((t) => t.id.equals('M1'))).getSingle();
    expect(row.mainReferee, 'Pedro');
    expect(row.teamAId, 3);
  });
}
