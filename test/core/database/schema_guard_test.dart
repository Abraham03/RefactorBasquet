// GUARD DEL ESQUEMA LOCAL — invariante I3 del "Plan Estructura Limpia.md".
//
// El refactor no puede tocar la base de datos: la app instalada debe seguir
// abriendo su .sqlite existente sin migrar. Este test es la primera línea de
// defensa (rápida, corre en cada `flutter test`); la segunda es el diff de
// `schema/base.json` contra un dump nuevo, descrito en el DoD del plan.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Localiza `app_database.dart` por nombre en vez de por ruta fija, para que
/// el guard sobreviva a los movimientos de archivos del refactor.
Future<String> _appDatabaseSource() async {
  final file = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere(
        (f) => f.path.replaceAll(r'\', '/').endsWith('/app_database.dart'),
        orElse: () => throw StateError('No se encontró app_database.dart'),
      );
  return file.readAsString();
}

void main() {
  group('Guard del esquema local (I3)', () {
    test('schemaVersion sigue en 4', () async {
      final source = await _appDatabaseSource();

      final match = RegExp(
        r'int get schemaVersion => (\d+);',
      ).firstMatch(source);

      expect(
        match,
        isNotNull,
        reason: 'No se encontró el getter schemaVersion en app_database.dart',
      );
      expect(
        match!.group(1),
        '4',
        reason:
            'Subir schemaVersion dispara una migración en los dispositivos '
            'ya instalados. Eso viola I3: ninguna fase del refactor debe '
            'tocar el esquema.',
      );
    });

    test('el archivo de base de datos conserva su nombre', () async {
      final source = await _appDatabaseSource();

      expect(
        source,
        contains("'basketball_league.sqlite'"),
        reason:
            'Renombrar el archivo hace que la app deje de encontrar los '
            'datos del usuario: partidos, equipos y jugadores desaparecen.',
      );
    });

    test('el dump de referencia existe y declara las 10 tablas', () async {
      final file = File('schema/base.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Falta schema/base.json. Regenera con:\n'
            '  dart run drift_dev schema dump '
            'lib/core/database/app_database.dart schema/base.json',
      );

      final dump =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final tables = (dump['entities'] as List)
          .where((e) => (e as Map)['type'] == 'table')
          .map((e) => ((e as Map)['data'] as Map)['name'] as String)
          .toSet();

      expect(
        tables,
        containsAll(<String>{
          'matches',
          'players',
          'match_rosters',
          'game_events',
          'tournaments',
          'venues',
          'teams',
          'tournament_teams',
          'fixtures',
          'officials',
        }),
      );
    });
  });
}
