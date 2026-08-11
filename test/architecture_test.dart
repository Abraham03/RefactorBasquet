// Las reglas de dependencia del plan, comprobadas por el analizador de tests.
//
// Escritas en el plan como "verificables por grep", pero un grep que nadie
// ejecuta no protege nada: una regla que no falla en CI es documentación, no
// arquitectura. Estos tests las hacen fallar solas.
//
// Cada regla lleva su lista de excepciones **explícita y razonada**. Añadir un
// archivo a esa lista debe costar una discusión, no un descuido.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Todos los .dart de `lib/`, sin los generados.
List<File> _libFiles() {
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();
}

String _rel(File f) => f.path.replaceAll(r'\', '/');

Iterable<String> _importsOf(File f) {
  return f
      .readAsLinesSync()
      .where((l) => l.startsWith('import '))
      .map((l) => l.split("'").length > 1 ? l.split("'")[1] : '');
}

void main() {
  group('Regla 2 — core/ y shared/ no conocen features/', () {
    // El composition root es la única excepción legítima: por definición
    // conoce todo lo que cablea.
    const allowed = {'lib/core/di/providers.dart'};

    test('ningún archivo de core/ o shared/ importa features/', () {
      final offenders = <String>[];
      for (final file in _libFiles()) {
        final path = _rel(file);
        if (!path.startsWith('lib/core/') && !path.startsWith('lib/shared/')) {
          continue;
        }
        if (allowed.contains(path)) continue;
        if (_importsOf(file).any((i) => i.contains('/features/'))) {
          offenders.add(path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'core/ y shared/ son infraestructura: si necesitan algo de '
            'una feature, es que ese algo no era de la feature.',
      );
    });
  });

  group('Regla 3 — domain/ no depende de frameworks', () {
    // Deuda conocida, con dueño: ambos son trabajo de la Fase 8, que parte
    // MatchGameController y libera a MatchFinalizer de AppDatabase.
    const knownDebt = {
      'lib/features/match/domain/services/match_finalizer.dart',
      'lib/features/match/domain/usecases/open_finished_match_usecase.dart',
    };

    test('ningún domain/ importa flutter, drift ni http', () {
      final offenders = <String>[];
      for (final file in _libFiles()) {
        final path = _rel(file);
        if (!path.contains('/domain/')) continue;
        if (knownDebt.contains(path)) continue;

        final bad = _importsOf(file).where(
          (i) =>
              i.startsWith('package:flutter/') ||
              i.startsWith('package:drift/') ||
              i.startsWith('package:http/'),
        );
        if (bad.isNotEmpty) offenders.add('$path -> ${bad.join(", ")}');
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'El dominio son las reglas del negocio: deben poder probarse '
            'sin Flutter y sobrevivir a un cambio de base de datos. Para '
            'anotaciones usa package:meta, no flutter/foundation.',
      );
    });

    test('la deuda conocida no crece', () {
      // Si un archivo sale de la lista, hay que quitarlo de aquí: así el
      // recuento no miente en el burn-down del plan.
      final stillOffending = knownDebt.where((path) {
        final file = File(path);
        if (!file.existsSync()) return false;
        return _importsOf(file).any(
          (i) =>
              i.startsWith('package:flutter/') ||
              i.startsWith('package:drift/') ||
              i.startsWith('package:http/'),
        );
      });

      expect(
        stillOffending.length,
        2,
        reason:
            'Si bajó, actualiza `knownDebt`. Si subió, alguien añadió una '
            'dependencia de framework al dominio.',
      );
    });
  });

  group('Regla — el marcador no depende de la pantalla de control', () {
    test('scoreboard/ no importa match/presentation', () {
      // Era la violación más clara: el contrato de cable importaba el archivo
      // del controller solo para alcanzar `MatchState`. Ahora la entidad vive
      // en `match/domain/entities/`.
      final offenders = <String>[];
      for (final file in _libFiles()) {
        final path = _rel(file);
        if (!path.startsWith('lib/features/scoreboard/')) continue;
        // Las pantallas del propio marcador sí pueden usar el controller.
        if (path.contains('/presentation/')) continue;

        if (_importsOf(file).any((i) => i.contains('match/presentation/'))) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty);
    });
  });

  group('Regla 3b — domain/ no depende de presentation/', () {
    test('ningún domain/ importa presentation/', () {
      // Es la inversión más grave: el dominio son las reglas del negocio y no
      // pueden necesitar la capa de UI para funcionar. `MatchFinalizer` y
      // `OutcomeChanger` dependían de `MatchGameController`; ahora piden un
      // `MatchFinalizationPort`, que declara las TRES cosas que usan en vez de
      // los ~55 métodos del controller.
      final offenders = <String>[];
      for (final file in _libFiles()) {
        final path = _rel(file);
        if (!path.contains('/domain/')) continue;
        if (_importsOf(file).any((i) => i.contains('/presentation/'))) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty);
    });
  });

  group('Regla — una sola fuente por dependencia', () {
    test('databaseProvider y apiClientProvider se declaran una vez', () {
      for (final name in ['databaseProvider', 'apiClientProvider']) {
        final declared = _libFiles()
            .where(
              (f) => RegExp('final $name\\s*=').hasMatch(f.readAsStringSync()),
            )
            .map(_rel)
            .toList();

        expect(
          declared,
          hasLength(1),
          reason:
              '$name está en ${declared.length} archivos: '
              '${declared.join(", ")}. Dos declaraciones significan dos '
              'instancias vivas y overrides que no surten efecto.',
        );
      }
    });
  });
}
