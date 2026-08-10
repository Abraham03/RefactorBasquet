// Prueba que el composition root es realmente único y sustituible.
//
// Estas dos cosas no eran ciertas antes de la Fase 2:
//   - `databaseProvider` y `apiServiceProvider` estaban declarados DOS veces
//     (en core/di y en los providers de catalog/tournament), así que convivían
//     dos instancias distintas de ApiService.
//   - `AppDatabase` era un singleton duro (`factory AppDatabase() => _instance`),
//     lo que hacía inútil cualquier override en un test: se devolvía siempre la
//     misma instancia de proceso, apuntando al .sqlite real del dispositivo.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/di/providers.dart';

// Se importan por las rutas por las que los consumían las pantallas, para
// probar que ambas resuelven al MISMO provider tras eliminar los duplicados.
import 'package:myapp/features/catalog/presentation/providers/catalog_providers.dart'
    as catalog;
import 'package:myapp/features/catalog/presentation/providers/tournament_providers.dart'
    as tournament;

void main() {
  group('Composition root sustituible', () {
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

    test('el override de databaseProvider llega de verdad al grafo', () {
      // Si AppDatabase siguiera siendo singleton, esto devolvería la BD real
      // del dispositivo en vez de la de memoria.
      expect(identical(container.read(databaseProvider), db), isTrue);
    });

    test('el DAO cuelga de la MISMA base de datos inyectada', () {
      // attachedDatabase recorre el cableado real: provider -> db.matchesDao.
      expect(
        identical(container.read(matchesDaoProvider).attachedDatabase, db),
        isTrue,
      );
    });

    test('apiServiceProvider devuelve una sola instancia por contenedor', () {
      expect(
        identical(
          container.read(apiServiceProvider),
          container.read(apiServiceProvider),
        ),
        isTrue,
      );
    });

    test('las rutas de import de catalog y tournament resuelven al mismo '
        'provider que el composition root', () {
      // Este es el bug que se corrigió: `catalog_providers` declaraba su propio
      // `apiServiceProvider`, así que una pantalla que lo importara de ahí
      // hablaba con una instancia distinta de la del resto de la app.
      expect(identical(catalog.apiServiceProvider, apiServiceProvider), isTrue);
      expect(identical(tournament.databaseProvider, databaseProvider), isTrue);
    });

    // El cierre de la BD (`ref.onDispose(db.close)`) no se cubre con un test:
    // `databaseProvider` sin override abre el .sqlite real vía path_provider,
    // que no existe en el host de tests. Un test permanentemente `skip` seria
    // ruido, asi que se deja documentado aqui.
  });

  group('AppDatabase ya no es un singleton', () {
    test('dos construcciones dan instancias distintas', () async {
      final a = AppDatabase.forTesting(NativeDatabase.memory());
      final b = AppDatabase.forTesting(NativeDatabase.memory());
      expect(identical(a, b), isFalse);
      await a.close();
      await b.close();
    });

    test('no queda rastro del patrón singleton en el código', () async {
      final raw = await File(
        'lib/core/database/app_database.dart',
      ).readAsString();
      // Se descartan los comentarios: la documentación de la clase EXPLICA el
      // patrón que se eliminó, así que un `contains` sobre el fuente crudo
      // daría un falso positivo.
      final code = raw
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(code, isNot(contains('static final AppDatabase _instance')));
      expect(code, isNot(contains('factory AppDatabase()')));
    });
  });

  group('Guard: ninguna dependencia se declara dos veces', () {
    test('databaseProvider y apiServiceProvider se declaran una sola vez', () {
      final declarations = <String, List<String>>{};

      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'),
              )) {
        final source = file.readAsStringSync();
        for (final name in ['databaseProvider', 'apiServiceProvider']) {
          if (RegExp('final $name\\s*=').hasMatch(source)) {
            declarations.putIfAbsent(name, () => []).add(file.path);
          }
        }
      }

      for (final entry in declarations.entries) {
        expect(
          entry.value,
          hasLength(1),
          reason:
              '${entry.key} está declarado en ${entry.value.length} '
              'archivos: ${entry.value.join(", ")}. Debe existir solo en '
              'core/di/providers.dart; los demás lo reexportan.',
        );
      }
    });
  });
}
