// FixtureRepository: bajada del calendario y consultas derivadas.
//
// Esta lógica estaba copiada en dos pantallas y las copias NO eran iguales:
// una omitía `isSynced`, así que el calendario recién bajado de la nube
// quedaba marcado como pendiente de subir y la siguiente sincronización lo
// reenviaba al servidor. Ese es el caso que fija el primer test.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/errors/app_exception.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/features/fixture/data/datasources/fixture_api.dart';
import 'package:myapp/features/fixture/data/repositories/fixture_repository.dart';

String fixturePayload(Map<String, dynamic> rounds) => jsonEncode({
  'status': 'success',
  'data': {'rounds': rounds},
});

Map<String, dynamic> match({
  required String id,
  String teamA = '3',
  String teamB = '4',
  String status = 'SCHEDULED',
}) => {
  'id': id,
  'team_a_id': teamA,
  'team_b_id': teamB,
  'team_a': 'Lobos',
  'team_b': 'Pumas',
  'status': status,
};

void main() {
  late AppDatabase db;

  FixtureRepository repoWith(String body, {int status = 200}) {
    final client = MockClient((_) async => http.Response(body, status));
    return FixtureRepository(db, FixtureApi(ApiClient(client: client)));
  }

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('refresh', () {
    test(
      'lo bajado de la nube NO queda marcado como pendiente de subir',
      () async {
        // El bug: `isSynced` tomaba su default (false) y `_uploadFixtures`
        // recoge todo lo que esté en false, así que el siguiente sync reenviaba
        // al servidor partidos que venían de él.
        final result = await repoWith(
          fixturePayload({
            'Jornada 1': [match(id: '100'), match(id: '101')],
          }),
        ).refresh('T1');

        expect(result.valueOrNull, 2);

        final saved = await db.select(db.fixtures).get();
        expect(saved, hasLength(2));
        expect(
          saved.every((f) => f.isSynced),
          isTrue,
          reason: 'vienen de la nube: ya están sincronizados',
        );
      },
    );

    test('el nombre de la jornada sale de la CLAVE del mapa', () async {
      await repoWith(
        fixturePayload({
          'Jornada 1': [match(id: '100')],
          'Jornada 2': [match(id: '200')],
        }),
      ).refresh('T1');

      final saved = await db.select(db.fixtures).get();
      expect(saved.map((f) => f.roundName).toSet(), {'Jornada 1', 'Jornada 2'});
    });

    test('reemplaza el calendario anterior del MISMO torneo', () async {
      await repoWith(
        fixturePayload({
          'Jornada 1': [match(id: '100')],
        }),
      ).refresh('T1');
      await repoWith(
        fixturePayload({
          'Jornada 1': [match(id: '200')],
        }),
      ).refresh('T1');

      final saved = await db.select(db.fixtures).get();
      expect(saved.map((f) => f.id), ['200']);
    });

    test('no toca el calendario de OTRO torneo', () async {
      await db
          .into(db.fixtures)
          .insert(
            FixturesCompanion.insert(
              id: 'otro',
              tournamentId: 'T2',
              roundName: 'J1',
              teamAId: '1',
              teamBId: '2',
              teamAName: 'X',
              teamBName: 'Y',
            ),
          );

      await repoWith(
        fixturePayload({
          'Jornada 1': [match(id: '100')],
        }),
      ).refresh('T1');

      final otro = await (db.select(
        db.fixtures,
      )..where((f) => f.tournamentId.equals('T2'))).get();
      expect(otro, hasLength(1));
    });

    test('un torneo sin calendario no borra lo que haya en local', () async {
      await repoWith(
        fixturePayload({
          'Jornada 1': [match(id: '100')],
        }),
      ).refresh('T1');

      // El backend responde sin `rounds`: aún no se ha generado el rol.
      final result = await repoWith(
        '{"status":"success","data":{}}',
      ).refresh('T1');

      expect(result.valueOrNull, 0);
      expect(
        await db.select(db.fixtures).get(),
        hasLength(1),
        reason: 'no hay nada nuevo, pero tampoco hay que destruir lo viejo',
      );
    });

    test('un fallo de red devuelve Err y no borra nada', () async {
      await repoWith(
        fixturePayload({
          'Jornada 1': [match(id: '100')],
        }),
      ).refresh('T1');

      final result = await repoWith('boom', status: 500).refresh('T1');

      expect(result.errorOrNull, isA<HttpStatusException>());
      expect(await db.select(db.fixtures).get(), hasLength(1));
    });
  });

  group('scheduledTeamPairs', () {
    test('devuelve las parejas ya programadas', () async {
      final result = await repoWith(
        fixturePayload({
          'Jornada 1': [match(id: '100', teamA: '3', teamB: '4')],
          'Jornada 2': [match(id: '200', teamA: '5', teamB: '6')],
        }),
      ).scheduledTeamPairs('T1');

      expect(result.valueOrNull, [(3, 4), (5, 6)]);
    });

    test('los cancelados no cuentan como enfrentamiento', () async {
      final result = await repoWith(
        fixturePayload({
          'Jornada 1': [
            match(id: '100', teamA: '3', teamB: '4', status: 'CANCELLED'),
            match(id: '101', teamA: '5', teamB: '6'),
          ],
        }),
      ).scheduledTeamPairs('T1');

      expect(result.valueOrNull, [(5, 6)]);
    });
  });
}
