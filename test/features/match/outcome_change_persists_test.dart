// El cambio de desenlace no llegaba nunca a la base local.
//
// La nube quedaba correcta —tiene su propio endpoint— pero el teléfono seguía
// mostrando el marcador viejo hasta la siguiente descarga del catálogo. La
// causa: todos los guardados pasaban por `_saveToDatabase`, que se salta la
// escritura cuando el partido está finalizado (para no revertirlo a
// IN_PROGRESS), y con ella se saltaba también el desenlace.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapp/core/constants/match_status.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
import 'package:myapp/features/match/domain/entities/match_restore_snapshot.dart';
import 'package:myapp/features/match/domain/services/outcome_changer.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';

void main() {
  // OutcomeChanger regenera el acta, y el PDF carga las fuentes de assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MatchGameController controller;

  /// Backend que puede aceptar o rechazar el cambio.
  MatchApi apiThat({required bool accepts}) => MatchApi(
    ApiClient(
      client: MockClient(
        (_) async => accepts
            ? http.Response('{"status":"success","data":{}}', 200)
            : http.Response('{"status":"error","message":"sin red"}', 500),
      ),
    ),
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    controller = MatchGameController(db.matchesDao);

    await db
        .into(db.matches)
        .insert(
          MatchesCompanion.insert(
            id: const Value('M1'),
            teamAName: 'Lobos',
            teamBName: 'Pumas',
            status: const Value(MatchStatus.finished),
            isSynced: const Value(true),
            scoreA: const Value(70),
            scoreB: const Value(65),
            observaciones: const Value('Sin novedad'),
          ),
        );

    await controller.restoreFromDatabase(
      const MatchRestoreSnapshot(
        matchId: 'M1',
        fixtureId: 'F1',
        rosterA: [],
        rosterB: [],
        startersA: {},
        startersB: {},
        tournamentId: 1,
        venueId: 7,
        teamAId: 3,
        teamBId: 4,
        mainReferee: 'Juan',
        auxReferee: 'Ana',
        scorekeeper: 'Luis',
      ),
      markFinished: true,
    );
  });

  tearDown(() async {
    await pumpEventQueue();
    controller.dispose();
    await db.close();
  });

  Future<BasketballMatch> row() =>
      (db.select(db.matches)..where((t) => t.id.equals('M1'))).getSingle();

  Future<void> change(MatchApi api) => OutcomeChanger(api).change(
    controller: controller,
    newOutcome: ForfeitStatus.teamB,
    observaciones: 'Protesta del entrenador',
    pdfParams: const OutcomePdfParams(
      teamAName: 'Lobos',
      teamBName: 'Pumas',
      tournamentName: 'Liga',
      categoryName: '',
      tournamentLogoUrl: '',
      refereeLogoUrl: '',
      venueName: 'Gimnasio',
      mainReferee: 'Juan',
      auxReferee: 'Ana',
      scorekeeper: 'Luis',
      coachA: 'Coach A',
      coachB: 'Coach B',
    ),
  );

  test('la nube acepta: el cambio baja a la base local', () async {
    await change(apiThat(accepts: true));

    final saved = await row();
    expect(saved.forfeitStatus, ForfeitStatus.teamB);
    expect(saved.observaciones, 'Protesta del entrenador');
    expect(
      saved.scoreA,
      controller.state.scoreA,
      reason: 'el marcador local debe coincidir con el del acta corregida',
    );
  });

  test('el partido sigue cerrado y sigue sincronizado', () async {
    // Ni se revierte a IN_PROGRESS ni se manda a la cola de pendientes: el
    // cambio acaba de viajar por su propio endpoint.
    await change(apiThat(accepts: true));

    final saved = await row();
    expect(saved.status, MatchStatus.finished);
    expect(
      saved.isSynced,
      isTrue,
      reason: 'volver a subirlo mandaría el acta entera con su PDF otra vez',
    );
  });

  test('la nube rechaza: la base local NO se toca', () async {
    // Es online-only. Guardar sin que el servidor lo acepte dejaría al
    // teléfono mostrando un resultado que la nube no tiene, y sin señal de
    // que están desalineados.
    await change(apiThat(accepts: false));

    final saved = await row();
    expect(saved.forfeitStatus, ForfeitStatus.none);
    expect(saved.observaciones, 'Sin novedad');
    expect(saved.scoreA, 70);
  });
}
