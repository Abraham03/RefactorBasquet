// El ciclo de vida del partido en curso.
//
// El plan pedía pasar `matchGameProvider` a `.family` + `autoDispose`. No
// aplica, y conviene dejar escrito por qué para no volver a intentarlo:
//
//   - `scoreboardBroadcasterProvider` escucha el estado a NIVEL DE APP para
//     emitirlo a la TV, sin saber de qué partido se trata. Con una `family`
//     habría que inventar un "id del partido activo", que es reintroducir el
//     mismo singleton con un rodeo.
//   - `autoDispose` nunca dispararía: ese mismo difusor mantiene la escucha
//     viva mientras la app existe.
//   - La app tiene **un partido en vivo a la vez** por naturaleza: una mesa de
//     anotación, un juego.
//
// Lo que el plan quería evitar de verdad —que el estado de un partido se
// filtre al siguiente— se resuelve con `ref.invalidate`. Esto lo comprueba en
// vez de darlo por hecho.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/di/providers.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('un partido nuevo arranca limpio', () {
    final state = container.read(matchGameProvider);

    expect(state.matchId, isEmpty);
    expect(state.scoreA, 0);
    expect(state.scoreB, 0);
    expect(state.currentPeriod, 1);
    expect(state.scoreLog, isEmpty);
    expect(state.playerStats, isEmpty);
  });

  test('invalidar borra TODO el partido anterior', () {
    // Es el mecanismo real de reseteo entre partidos: las pantallas llaman a
    // `ref.invalidate(matchGameProvider)` al terminar. Si dejara restos, el
    // partido siguiente arrancaría con el marcador del anterior.
    final controller = container.read(matchGameProvider.notifier);
    controller
      ..initializeNewMatch(
        matchId: 'M1',
        rosterA: const [],
        rosterB: const [],
        startersA: const {},
        startersB: const {},
        tournamentId: 1,
        venueId: 1,
        teamAId: 3,
        teamBId: 4,
        mainReferee: 'Juan',
        auxReferee: 'Ana',
        scorekeeper: 'Luis',
      )
      ..setObservaciones('Hubo protesta')
      ..nextPeriod();

    expect(container.read(matchGameProvider).matchId, 'M1');

    container.invalidate(matchGameProvider);

    final fresh = container.read(matchGameProvider);
    expect(fresh.matchId, isEmpty);
    expect(fresh.currentPeriod, 1, reason: 'no arrastra el período');
    expect(fresh.observaciones, isEmpty, reason: 'no arrastra observaciones');
    expect(fresh.mainReferee, isEmpty, reason: 'no arrastra los árbitros');
    expect(fresh.scoreLog, isEmpty);
  });

  test('invalidar entrega un notifier NUEVO, no el mismo reseteado', () {
    // Importa porque el controller guarda estado fuera de `MatchState`: el
    // reloj y la pila de deshacer. Reutilizar la instancia dejaría el
    // temporizador del partido anterior corriendo.
    final first = container.read(matchGameProvider.notifier);
    container.invalidate(matchGameProvider);
    final second = container.read(matchGameProvider.notifier);

    expect(identical(first, second), isFalse);
  });

  test('la pila de deshacer no sobrevive al partido', () {
    // Deshacer después de invalidar no debe devolver el marcador del partido
    // anterior.
    final controller = container.read(matchGameProvider.notifier)
      ..setObservaciones('algo');

    container.invalidate(matchGameProvider);
    container.read(matchGameProvider.notifier).undo();

    expect(container.read(matchGameProvider).observaciones, isEmpty);
    expect(controller, isNotNull);
  });

  test('el reloj arranca parado', () {
    // Un partido recién abierto no debe estar corriendo: el árbitro lo pone
    // en marcha con el salto inicial.
    expect(container.read(matchGameProvider).isRunning, isFalse);
  });

  test('el estado por defecto es el mismo que construye MatchState()', () {
    // Candado: si alguien añade un campo con un valor inicial distinto en el
    // provider, el partido nuevo dejaría de arrancar limpio.
    expect(container.read(matchGameProvider), const MatchState());
  });
}
