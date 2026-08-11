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
    // Esta regla tuvo dos excepciones toleradas hasta la Fase 8:
    // `match_finalizer.dart` y `open_finished_match_usecase.dart`, ambos con
    // un `AppDatabase` dentro y consultas drift directas. Ya no existen:
    //   - el finalizador pide ahora un `MatchClosingRepository` (contrato de
    //     dominio, implementado con drift en `data/`);
    //   - el usecase no tenía ninguna regla de negocio —solo decidía de dónde
    //     traer cada dato, y recibía un `Fixture` de drift—, así que se movió
    //     a `data/repositories/finished_match_loader.dart`, que es su sitio.
    //
    // Por eso la lista de deuda desapareció en lugar de quedarse vacía: una
    // lista vacía invita a volver a llenarla.

    test('ningún domain/ importa flutter, drift ni http', () {
      final offenders = <String>[];
      for (final file in _libFiles()) {
        final path = _rel(file);
        if (!path.contains('/domain/')) continue;

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

    test('el dominio no sostiene una base de datos', () {
      // El síntoma concreto de la deuda que cerró la Fase 8: un campo
      // `AppDatabase` dentro de `domain/`. Se comprueba aparte del import
      // porque es la forma en que reaparecería —alguien pasando el `db` a un
      // servicio de dominio «solo para esta consulta».
      final offenders = <String>[];
      for (final file in _libFiles()) {
        final path = _rel(file);
        if (!path.contains('/domain/')) continue;
        // Sin comentarios: los contratos de `domain/` explican en su doc de
        // qué deuda nacieron, y nombrar `AppDatabase` ahí no es depender de
        // ella.
        final code = file
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (code.contains('AppDatabase')) offenders.add(path);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Un servicio de dominio que necesita datos declara el contrato '
            'que usa (p. ej. `MatchClosingRepository`) y deja que `data/` lo '
            'implemente con drift.',
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
