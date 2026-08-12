// Regresión de campo: el acta de un partido jugado sin cobertura se subía
// sin los escudos del torneo y de la asociación.
//
// La URL sí estaba disponible offline —`tournaments.logo_url` se guarda en la
// descarga del catálogo—, pero los bytes no: `PdfImageLoader` iba siempre a la
// red. Y como el PDF se escribe en disco al cerrar el partido y luego se sube
// ESE archivo, no uno regenerado, el hueco se volvía permanente.
//
// El servidor local se apaga a propósito a mitad del test: es la única forma
// honesta de comprobar que la segunda acta no depende de la red.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myapp/shared/services/image_loader_service.dart';
import 'package:myapp/shared/services/image_store.dart';

void main() {
  late Directory root;
  late FileImageStore store;
  late HttpServer server;
  late String logoUrl;
  var hits = 0;

  // JPEG de verdad, mínimo: `pw.MemoryImage` valida el formato, así que unos
  // magic bytes sueltos no sirven. El JPEG además pasa por la ruta de copia
  // directa, sin decodificar, que es lo que aquí interesa medir.
  final jpeg = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 8, height: 8)),
  );

  setUp(() async {
    hits = 0;
    root = await Directory.systemTemp.createTemp('offline_logo_test');
    store = FileImageStore(root: () async => root);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      hits++;
      if (request.uri.path.contains('no-existe')) {
        request.response.statusCode = 404;
      } else {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('image', 'jpeg')
          ..add(jpeg);
      }
      await request.response.close();
    });
    logoUrl = 'http://127.0.0.1:${server.port}/logo.jpg';
  });

  tearDown(() async {
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('el acta sale con logo aunque la red se haya caído', () async {
    // Primera acta, con cobertura.
    expect(await PdfImageLoader.fromNetwork(logoUrl, cache: store), isNotNull);
    expect(hits, 1);

    // Se cae la red: el partido siguiente se juega en el gimnasio sin señal.
    await server.close(force: true);

    expect(
      await PdfImageLoader.fromNetwork(logoUrl, cache: store),
      isNotNull,
      reason: 'sin caché esto lanzaba y el acta salía sin escudo',
    );
  });

  test('sin caché, sin red no hay logo', () async {
    // El comportamiento anterior, fijado para que quede claro qué se arregló.
    await server.close(force: true);

    await expectLater(PdfImageLoader.fromNetwork(logoUrl), throwsA(anything));
  });

  test('la segunda acta no vuelve a bajar el logo', () async {
    await PdfImageLoader.fromNetwork(logoUrl, cache: store);
    await PdfImageLoader.fromNetwork(logoUrl, cache: store);

    expect(hits, 1, reason: 'la caché evita el viaje, no solo lo sobrevive');
  });

  group('calentar la caché', () {
    test('deja el logo listo antes de que haga falta', () async {
      // Lo hace la descarga del catálogo, que siempre ocurre con red.
      expect(await PdfImageLoader.warmCache(logoUrl, store), isTrue);

      await server.close(force: true);
      expect(
        await PdfImageLoader.fromNetwork(logoUrl, cache: store),
        isNotNull,
      );
    });

    test('no repite la descarga de lo ya cacheado', () async {
      await PdfImageLoader.warmCache(logoUrl, store);
      await PdfImageLoader.warmCache(logoUrl, store);

      expect(hits, 1);
    });

    test('sin red devuelve false y no lanza', () async {
      // Calentar es un extra: no puede tumbar una sincronización que sí
      // descargó el catálogo entero.
      await server.close(force: true);

      expect(await PdfImageLoader.warmCache(logoUrl, store), isFalse);
    });

    test('con refresh se vuelve a bajar el escudo', () async {
      // El backend puede sustituir el logo dejando la misma URL. La descarga
      // del catálogo fuerza el refresco; si no, el acta imprimiría el viejo.
      await PdfImageLoader.warmCache(logoUrl, store);
      await PdfImageLoader.warmCache(logoUrl, store, refresh: true);

      expect(hits, 2);
    });

    test('una URL vacía no se intenta', () async {
      expect(await PdfImageLoader.warmCache('', store), isFalse);
      expect(await PdfImageLoader.warmCache(null, store), isFalse);
      expect(hits, 0);
    });
  });

  test('un 404 no envenena la caché', () async {
    // Si se guardara la página de error, el acta se quedaría sin escudo para
    // siempre aunque el logo volviera a estar disponible.
    final url = 'http://127.0.0.1:${server.port}/no-existe.jpg';

    expect(await PdfImageLoader.warmCache(url, store), isFalse);
    expect(await store.read(url), isNull);
  });
}
