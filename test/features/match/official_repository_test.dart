// OfficialRepository: recuperación y decodificación de firmas.
//
// Las firmas acaban dibujadas en el acta en PDF. Un base64 corrupto no debe
// tumbar el cierre del partido —el árbitro está esperando— sino degradar a
// "sin firma". Eso nunca se había probado.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/features/match/data/repositories/official_repository.dart';
import 'package:myapp/features/match/domain/repositories/official_repository_contract.dart';

void main() {
  late AppDatabase db;
  late OfficialRepositoryContract repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Se declara por el CONTRATO, no por la clase: si mañana `MatchFinalizer`
    // recibe otra implementación, este test sigue describiendo lo que exige.
    repo = OfficialRepository(db);
  });

  tearDown(() async => db.close());

  Future<void> seedOfficial({
    required String id,
    required String name,
    required String role,
    String? signature,
  }) {
    return db
        .into(db.officials)
        .insert(
          OfficialsCompanion.insert(
            id: id,
            name: name,
            role: Value(role),
            signatureData: Value(signature),
          ),
        );
  }

  test('devuelve las dos firmas decodificadas a bytes', () async {
    final bytes = base64Encode([1, 2, 3, 4]);
    await seedOfficial(
      id: '1',
      name: 'Juan',
      role: 'ARBITRO_PRINCIPAL',
      signature: bytes,
    );
    await seedOfficial(
      id: '2',
      name: 'Ana',
      role: 'ARBITRO_AUXILIAR',
      signature: bytes,
    );

    final result = await repo.getRefereeSignatures(
      mainRefereeName: 'Juan',
      auxRefereeName: 'Ana',
    );

    expect(result.main, [1, 2, 3, 4]);
    expect(result.aux, [1, 2, 3, 4]);
  });

  test('el rol importa: un mismo nombre con otro rol no cuenta', () async {
    // Una persona puede figurar como principal en un partido y auxiliar en
    // otro; buscar solo por nombre traería la firma equivocada.
    await seedOfficial(
      id: '1',
      name: 'Juan',
      role: 'ARBITRO_AUXILIAR',
      signature: base64Encode([9]),
    );

    final result = await repo.getRefereeSignatures(
      mainRefereeName: 'Juan',
      auxRefereeName: 'Nadie',
    );

    expect(result.main, isNull);
  });

  test('un árbitro que no existe da null, no una excepción', () async {
    final result = await repo.getRefereeSignatures(
      mainRefereeName: 'Fantasma',
      auxRefereeName: 'Otro',
    );

    expect(result.main, isNull);
    expect(result.aux, isNull);
  });

  test(
    'una firma corrupta degrada a null en vez de tumbar el cierre',
    () async {
      // Este es el caso que importa: el partido termina igual, el acta sale sin
      // esa firma. Propagar la excepción dejaría al árbitro sin poder cerrar.
      await seedOfficial(
        id: '1',
        name: 'Juan',
        role: 'ARBITRO_PRINCIPAL',
        signature: 'esto no es base64 !!!',
      );

      final result = await repo.getRefereeSignatures(
        mainRefereeName: 'Juan',
        auxRefereeName: 'Nadie',
      );

      expect(result.main, isNull);
    },
  );

  test('una firma vacía se trata como ausente', () async {
    await seedOfficial(
      id: '1',
      name: 'Juan',
      role: 'ARBITRO_PRINCIPAL',
      signature: '',
    );

    final result = await repo.getRefereeSignatures(
      mainRefereeName: 'Juan',
      auxRefereeName: 'Nadie',
    );

    expect(result.main, isNull);
  });
}
