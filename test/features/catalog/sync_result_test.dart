// `SyncResult` es lo único que la pantalla ve de una subida, así que si
// miente, miente al árbitro.

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/catalog/domain/entities/sync_result.dart';

void main() {
  test('sin fallos, no hay nada que reportar', () {
    const result = SyncResult(tournaments: 2, teams: 3);

    expect(result.hasFailures, isFalse);
    expect(result.toFailureSummary(), isEmpty);
  });

  test('los fallos se cuentan y se describen', () {
    const result = SyncResult(
      teams: 1,
      failures: ['Equipo Lobos: sin conexión', 'Sede Gimnasio: HTTP 500'],
    );

    expect(result.hasFailures, isTrue);
    expect(result.toFailureSummary(), contains('2 elementos'));
    expect(result.toFailureSummary(), contains('Equipo Lobos'));
    expect(result.toFailureSummary(), contains('Sede Gimnasio'));
  });

  test('subir algo y fallar en otra cosa NO es una subida limpia', () {
    // El caso que la pantalla presentaba como "Sincronización exitosa": el
    // recuento de éxitos era correcto y los fallos no aparecían por ningún
    // lado.
    const result = SyncResult(teams: 5, failures: ['Equipo Pumas: HTTP 500']);

    expect(result.toSummary(), contains('5 Equipos'));
    expect(
      result.hasFailures,
      isTrue,
      reason: 'la pantalla decide el mensaje con esto',
    );
  });

  test('copyWith arrastra los fallos', () {
    // El repositorio va acumulando con copyWith entidad por entidad; si este
    // campo se perdiera por el camino, los fallos volverían a desaparecer.
    const base = SyncResult(failures: ['Torneo Liga: timeout']);

    expect(base.copyWith(teams: 4).failures, base.failures);
    expect(base.copyWith(teams: 4).hasFailures, isTrue);
  });
}
