// Red de seguridad del acta antes de trocear `_buildDocument`.
//
// No es un golden de bytes: `pw.Document` estampa una fecha de creación, así
// que dos ejecuciones del MISMO acta no dan los mismos bytes. Lo que se
// comprueba es que el documento se genera —que es donde muerde un refactor de
// dibujo: una coordenada mal pasada no rompe el PDF, pero un parámetro
// cruzado o un índice fuera de rango lanza y el árbitro se queda sin acta con
// el partido ya cerrado.

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/reports/data/pdf_generator.dart';

MatchState _matchWith({
  int scoreA = 0,
  int scoreB = 0,
  int period = 1,
  String forfeit = 'NONE',
  Map<String, PlayerStats> players = const {},
  List<ScoreEvent> log = const [],
}) {
  return MatchState(
    scoreA: scoreA,
    scoreB: scoreB,
    currentPeriod: period,
    forfeitStatus: forfeit,
    playerStats: players,
    scoreLog: log,
  );
}

PlayerStats _player(String name, int number, {int points = 0, int fouls = 0}) {
  return PlayerStats(
    dbId: number,
    playerName: name,
    playerNumber: '$number',
    points: points,
    fouls: fouls,
    isStarter: true,
    isOnCourt: true,
    hasPlayed: true,
  );
}

void main() {
  // `generateBytes` carga las fuentes Roboto desde los assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> expectValidPdf(Future<List<int>> future) async {
    final bytes = await future;

    expect(bytes.length, greaterThan(1000), reason: 'un acta vacía no vale');
    expect(
      String.fromCharCodes(bytes.take(5)),
      '%PDF-',
      reason: 'la cabecera del formato',
    );
    expect(
      String.fromCharCodes(bytes.skip(bytes.length - 6)),
      contains('%%EOF'),
      reason: 'documento truncado: el render se cortó a medias',
    );
  }

  test('genera un acta de un partido normal', () async {
    await expectValidPdf(
      PdfGenerator.generateBytes(
        _matchWith(
          scoreA: 78,
          scoreB: 65,
          period: 4,
          players: {
            '9': _player('Pedro', 12, points: 20, fouls: 3),
            '10': _player('Luis', 7, points: 8, fouls: 1),
          },
        ),
        'Lobos',
        'Pumas',
        tournamentName: 'Liga Municipal',
        mainReferee: 'Juan',
        auxReferee: 'Ana',
        scorekeeper: 'Luis',
      ),
    );
  });

  test('genera un acta sin jugadores ni eventos', () async {
    // El caso degenerado: partido creado y cerrado sin anotar nada. Los
    // bucles de dibujo de roster iteran sobre listas vacías.
    await expectValidPdf(
      PdfGenerator.generateBytes(_matchWith(), 'Lobos', 'Pumas'),
    );
  });

  test('los acentos no revientan el render', () async {
    // La Helvetica por defecto del paquete no soporta acentos y hace fallar
    // el render. Por eso se cargan las Roboto desde assets; esto lo vigila.
    await expectValidPdf(
      PdfGenerator.generateBytes(
        _matchWith(players: {'1': _player('Jesús Ñuño', 4)}),
        'Atlético',
        'Águilas',
        tournamentName: 'Categoría Única',
        venueName: 'Gimnasio Municipal',
        mainReferee: 'José Ramírez',
      ),
    );
  });

  test('genera un acta con prórroga', () async {
    await expectValidPdf(
      PdfGenerator.generateBytes(
        _matchWith(scoreA: 90, scoreB: 88, period: 5),
        'Lobos',
        'Pumas',
      ),
    );
  });

  test('genera un acta con inasistencia', () async {
    await expectValidPdf(
      PdfGenerator.generateBytes(
        _matchWith(forfeit: ForfeitStatus.teamB),
        'Lobos',
        'Pumas',
      ),
    );
  });

  test('genera un acta con faltas de banquillo en el log', () async {
    // Las técnicas de entrenador y banca se dibujan en su propia sección, y
    // el filtro que las separa de las personales cambió en la Fase 9.
    await expectValidPdf(
      PdfGenerator.generateBytes(
        _matchWith(
          period: 2,
          players: {'1': _player('Pedro', 12, fouls: 2)},
          log: [
            const ScoreEvent(
              period: 1,
              teamId: TeamSide.home,
              playerId: 'Entrenador',
              playerNumber: '',
              points: 0,
              scoreAfter: 0,
              type: EventType.coach,
            ),
            const ScoreEvent(
              period: 1,
              teamId: TeamSide.home,
              playerId: 'Banca',
              playerNumber: '',
              points: 0,
              scoreAfter: 0,
              type: EventType.bench,
            ),
            const ScoreEvent(
              period: 1,
              teamId: TeamSide.home,
              playerId: '1',
              playerNumber: '12',
              points: 2,
              scoreAfter: 2,
              type: EventType.point2,
            ),
          ],
        ),
        'Lobos',
        'Pumas',
      ),
    );
  });
}
