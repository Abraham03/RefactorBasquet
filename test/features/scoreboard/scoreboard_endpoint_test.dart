import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/scoreboard/data/scoreboard_endpoint.dart';

void main() {
  group('ScoreboardEndpoint.parseUserInput', () {
    test('IP sin puerto usa el puerto por defecto', () {
      final uri = ScoreboardEndpoint.parseUserInput('192.168.1.5');
      expect(uri, isNotNull);
      expect(uri!.host, '192.168.1.5');
      expect(uri.port, 8080);
      expect(uri.scheme, 'ws');
    });

    test('respeta el puerto explícito', () {
      final uri = ScoreboardEndpoint.parseUserInput('192.168.1.5:8081');
      expect(uri!.port, 8081);
    });

    test('acepta URI ws:// completa', () {
      final uri = ScoreboardEndpoint.parseUserInput('ws://10.0.0.4:8082');
      expect(uri!.host, '10.0.0.4');
      expect(uri.port, 8082);
    });

    test('tolera espacios alrededor', () {
      expect(ScoreboardEndpoint.parseUserInput('  192.168.1.5  ')!.host,
          '192.168.1.5');
    });

    test('rechaza entradas inválidas', () {
      for (final bad in [
        '',
        '   ',
        '999.1.1.1',
        '192.168.1.5:99999',
        '192.168.1.5:abc',
        'http://192.168.1.5',
        '192.168.1.5:8080:9',
      ]) {
        expect(ScoreboardEndpoint.parseUserInput(bad), isNull,
            reason: 'debería rechazar "$bad"');
      }
    });
  });

  group('ScoreboardEndpoint.candidatesForInput', () {
    test('sin puerto explícito prueba todos los candidatos', () {
      final list = ScoreboardEndpoint.candidatesForInput('192.168.1.5');
      expect(list.length, ScoreboardEndpoint.candidatePorts.length);
      expect(list.map((u) => u.port), ScoreboardEndpoint.candidatePorts);
    });

    test('con puerto explícito respeta solo ese', () {
      final list = ScoreboardEndpoint.candidatesForInput('192.168.1.5:8082');
      expect(list.length, 1);
      expect(list.single.port, 8082);
    });
  });

  test('loopbackCandidates cubre todos los puertos', () {
    final list = ScoreboardEndpoint.loopbackCandidates();
    expect(list.length, ScoreboardEndpoint.candidatePorts.length);
    expect(list.every((u) => u.host == '127.0.0.1'), isTrue);
  });

  group('validationError', () {
    test('mensaje útil cuando está vacío', () {
      expect(ScoreboardEndpoint.validationError(''), isNotNull);
    });

    test('null cuando es válido', () {
      expect(ScoreboardEndpoint.validationError('192.168.1.5'), isNull);
    });
  });
}
