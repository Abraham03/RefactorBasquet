// La caché en disco de imágenes remotas, que usan tanto el acta como las
// pantallas.
//
// Nació de un fallo de campo con los escudos: `PdfImageLoader` iba SIEMPRE a
// la red, así que sin cobertura el acta se generaba pelada, se guardaba en
// disco y al recuperar el wifi se subía ese mismo archivo —nunca uno
// regenerado—, con lo que el hueco quedaba para siempre en la nube.
//
// Las fotos de los jugadores tenían el mismo problema por otra vía: el
// `ImageCache` de Flutter es solo de memoria y muere con el proceso.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/shared/services/image_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late FileImageStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('image_store_test');
    store = FileImageStore(root: () async => root);
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

    final otra = FileImageStore(root: () async => root);
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
        FileImageStore.fileNameFor('https://a.mx/uploads/logo.png'),
        isNot(FileImageStore.fileNameFor('https://b.mx/uploads/logo.png')),
      );
    },
  );

  test('el nombre de archivo es estable entre ejecuciones', () async {
    // Si el hash cambiara, toda la caché quedaría huérfana en cada versión y
    // el modo offline volvería a salir sin logos.
    expect(
      FileImageStore.fileNameFor('https://vanball.com.mx/uploads/logos/a.png'),
      FileImageStore.fileNameFor('https://vanball.com.mx/uploads/logos/a.png'),
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
    final dir = Directory(p.join(root.path, store.folderName));
    await dir.create(recursive: true);
    await File(
      p.join(dir.path, FileImageStore.fileNameFor('https://x/roto.png')),
    ).writeAsBytes([]);

    expect(await store.read('https://x/roto.png'), isNull);
  });

  test('un directorio ilegible no lanza, solo devuelve null', () async {
    // La generación del acta no puede caerse porque el disco falle.
    final roto = FileImageStore(
      root: () async => throw const FileSystemException('sin disco'),
    );

    expect(await roto.read('https://x/logo.png'), isNull);
    await expectLater(roto.write('https://x/logo.png', bytes), completes);
  });

  group('tope de tamaño', () {
    // Los escudos del acta van sin tope; las fotos de jugadores, no: son
    // cientos y el catálogo las renueva temporada a temporada, así que sin
    // límite la carpeta solo crecería.
    Uint8List blob(int size) => Uint8List(size)..fillRange(0, size, 7);

    test('sin tope no se borra nada', () async {
      for (var i = 0; i < 20; i++) {
        await store.write('https://x/$i.png', blob(1000));
      }

      expect(await store.read('https://x/0.png'), isNotNull);
    });

    test('al pasarse, la carpeta vuelve por debajo del tope', () async {
      final acotado = FileImageStore(
        root: () async => root,
        folderName: 'acotado',
        maxBytes: 5000,
      );

      for (var i = 0; i < 10; i++) {
        await acotado.write('https://x/$i.png', blob(1000));
      }

      final quedan = await Directory(
        p.join(root.path, 'acotado'),
      ).list().length;

      expect(quedan, lessThan(10), reason: 'se escribieron 10 KB en 5 KB');
      expect(quedan * 1000, lessThanOrEqualTo(5000));
    });

    test('lo último escrito sobrevive al recorte', () async {
      // No se comprueba QUÉ archivo concreto cae: la granularidad de las
      // marcas de tiempo del sistema hace que varias escrituras del mismo
      // instante se ordenen de forma arbitraria. Da igual cuál de ellas se
      // vaya —el precio es una descarga— pero lo recién pedido debe quedarse.
      final acotado = FileImageStore(
        root: () async => root,
        folderName: 'reciente',
        maxBytes: 3000,
      );

      for (var i = 0; i < 5; i++) {
        await acotado.write('https://x/$i.png', blob(1000));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }

      expect(await acotado.read('https://x/4.png'), isNotNull);
    });

    test('el recorte deja margen, no se queda al filo', () async {
      // Si vaciara justo hasta el tope, la siguiente escritura volvería a
      // recortar: una pasada por la carpeta entera en cada foto nueva.
      final acotado = FileImageStore(
        root: () async => root,
        folderName: 'margen',
        maxBytes: 5000,
      );
      for (var i = 0; i < 10; i++) {
        await acotado.write('https://x/$i.png', blob(1000));
      }

      final dir = Directory(p.join(root.path, 'margen'));
      final total = await dir.list().cast<File>().fold<int>(
        0,
        (sum, f) => sum + f.lengthSync(),
      );

      expect(total, lessThanOrEqualTo(4000));
    });
  });

  test('NoImageStore no guarda nada', () async {
    const nada = NoImageStore();
    await nada.write('https://x/logo.png', bytes);

    expect(await nada.read('https://x/logo.png'), isNull);
  });
}
