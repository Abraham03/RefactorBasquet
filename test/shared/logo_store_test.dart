// La caché de logos: lo que permite que un acta jugada sin cobertura salga
// con los escudos del torneo y de la asociación.
//
// El fallo de campo: `PdfImageLoader` iba SIEMPRE a la red. Sin cobertura el
// acta se generaba pelada, se guardaba en disco, y al recuperar el wifi se
// subía ese mismo archivo —nunca uno regenerado—, así que el hueco quedaba
// para siempre en la nube.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/shared/services/logo_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late FileLogoStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('logo_store_test');
    store = FileLogoStore(root: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  test('lo que se guarda se vuelve a leer', () async {
    await store.write('https://x/logo.png', bytes);

    expect(await store.read('https://x/logo.png'), bytes);
  });

  test('una URL que nunca se guardó devuelve null', () async {
    expect(await store.read('https://x/jamas.png'), isNull);
  });

  test('otra instancia lee lo que dejó la primera', () async {
    // Es el caso real: se calienta al descargar el catálogo y se lee en otra
    // sesión de la app, al generar el acta.
    await store.write('https://x/logo.png', bytes);

    final otra = FileLogoStore(root: () async => root);
    expect(await otra.read('https://x/logo.png'), bytes);
  });

  test('dos URLs distintas no se pisan', () async {
    await store.write('https://a/logo.png', bytes);
    await store.write('https://b/logo.png', Uint8List.fromList([9, 9]));

    expect(await store.read('https://a/logo.png'), bytes);
    expect(await store.read('https://b/logo.png'), [9, 9]);
  });

  test(
    'mismo nombre de archivo en servidores distintos NO colisiona',
    () async {
      // Por esto se hashea la URL entera y no se reutiliza el basename: dos
      // torneos sirviendo su `logo.png` acabarían compartiendo escudo.
      expect(
        FileLogoStore.fileNameFor('https://a.mx/uploads/logo.png'),
        isNot(FileLogoStore.fileNameFor('https://b.mx/uploads/logo.png')),
      );
    },
  );

  test('el nombre de archivo es estable entre ejecuciones', () async {
    // Si el hash cambiara, toda la caché quedaría huérfana en cada versión y
    // el modo offline volvería a salir sin logos.
    expect(
      FileLogoStore.fileNameFor('https://vanball.com.mx/uploads/logos/a.png'),
      FileLogoStore.fileNameFor('https://vanball.com.mx/uploads/logos/a.png'),
    );
  });

  test('reescribir la misma URL deja la versión nueva', () async {
    await store.write('https://x/logo.png', bytes);
    await store.write('https://x/logo.png', Uint8List.fromList([7]));

    expect(await store.read('https://x/logo.png'), [7]);
  });

  test('guardar bytes vacíos no crea archivo', () async {
    // Una respuesta vacía no es un logo. Si se guardara, la caché serviría
    // ese vacío para siempre y el acta nunca recuperaría el escudo.
    await store.write('https://x/vacio.png', Uint8List(0));

    expect(await store.read('https://x/vacio.png'), isNull);
  });

  test('un archivo truncado a cero se ignora', () async {
    final dir = Directory(p.join(root.path, FileLogoStore.folderName));
    await dir.create(recursive: true);
    await File(
      p.join(dir.path, FileLogoStore.fileNameFor('https://x/roto.png')),
    ).writeAsBytes([]);

    expect(await store.read('https://x/roto.png'), isNull);
  });

  test('un directorio ilegible no lanza, solo devuelve null', () async {
    // La generación del acta no puede caerse porque el disco falle.
    final roto = FileLogoStore(
      root: () async => throw const FileSystemException('sin disco'),
    );

    expect(await roto.read('https://x/logo.png'), isNull);
    await expectLater(roto.write('https://x/logo.png', bytes), completes);
  });

  test('NoLogoStore no guarda nada', () async {
    const nada = NoLogoStore();
    await nada.write('https://x/logo.png', bytes);

    expect(await nada.read('https://x/logo.png'), isNull);
  });
}
