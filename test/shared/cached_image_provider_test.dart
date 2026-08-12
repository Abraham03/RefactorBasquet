// Las fotos de los jugadores y los escudos de equipo se guardan en disco.
//
// `Image.network` solo usa el `ImageCache` de memoria, que muere con el
// proceso: sin cobertura, la pantalla de titulares caía al placeholder aunque
// la foto se hubiera visto mil veces.
//
// Los tests no montan widgets: lo que se comprueba es de dónde salen los
// bytes y cuándo se viaja a la red, que es lo que decide si la pantalla se
// pinta sin señal.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:myapp/shared/services/cached_image_provider.dart';
import 'package:myapp/shared/services/image_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late FileImageStore store;
  var hits = 0;
  var offline = false;

  final png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));

  const url = 'https://vanball.com.mx/uploads/players/9.png';

  /// Deja a Flutter sin memoria de lo ya resuelto, incluidas las imágenes
  /// «vivas»: es lo que permite comprobar de dónde salen los bytes la segunda
  /// vez en lugar de medir su caché interno.
  void forgetDecoded() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  setUp(() async {
    hits = 0;
    offline = false;
    // El `ImageCache` de Flutter es global al proceso y sobrevive entre
    // tests: sin vaciarlo, uno resolvería con lo que dejó el anterior.
    forgetDecoded();
    root = await Directory.systemTemp.createTemp('cached_image_test');
    store = FileImageStore(root: () async => root);

    CachedImage.clientFactory = () => MockClient((request) async {
      hits++;
      if (offline) throw const SocketException('sin red');
      if (request.url.path.contains('no-existe')) {
        return http.Response('not found', 404);
      }
      return http.Response.bytes(png, 200);
    });
  });

  tearDown(() async {
    CachedImage.clientFactory = http.Client.new;
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Fuerza la carga completa del proveedor y devuelve si terminó en imagen.
  ///
  /// El listener se quita al terminar: mientras haya uno, Flutter mantiene la
  /// imagen «viva» y la reutiliza aunque se vacíe el caché, lo que haría pasar
  /// por arte de magia los tests que simulan quedarse sin red.
  Future<bool> resolves(CachedImage provider) async {
    final completer = Completer<bool>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, __) {
        if (!completer.isCompleted) completer.complete(true);
      },
      onError: (_, __) {
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    stream.addListener(listener);

    final result = await completer.future;
    stream.removeListener(listener);
    return result;
  }

  test('la primera vez se baja y se guarda', () async {
    expect(await resolves(CachedImage(url, store: store)), isTrue);

    expect(hits, 1);
    expect(
      await store.read(url),
      isNotNull,
      reason: 'sin esto, la siguiente vez sin red no habría foto',
    );
  });

  test('la segunda vez sale del disco, sin viaje a la red', () async {
    await store.write(url, png);

    expect(await resolves(CachedImage(url, store: store)), isTrue);
    expect(hits, 0);
  });

  test('sin red pero con caché, la foto se ve', () async {
    // El caso que se quería arreglar: el gimnasio sin señal.
    await resolves(CachedImage(url, store: store));
    offline = true;
    forgetDecoded();

    expect(await resolves(CachedImage(url, store: store)), isTrue);
  });

  test('sin red y sin caché falla, para que salga el placeholder', () async {
    // Si no lanzara, el widget se quedaría en blanco en vez de mostrar el
    // icono de sustitución.
    offline = true;

    expect(await resolves(CachedImage(url, store: store)), isFalse);
  });

  test('un 404 no se guarda como si fuera la foto', () async {
    const roto = 'https://vanball.com.mx/uploads/players/no-existe.png';

    expect(await resolves(CachedImage(roto, store: store)), isFalse);
    expect(await store.read(roto), isNull);
  });

  test('sin almacén se comporta como antes: solo red', () async {
    expect(
      await resolves(const CachedImage(url, store: NoImageStore())),
      isTrue,
    );
    expect(hits, 1);

    offline = true;
    forgetDecoded();
    expect(
      await resolves(const CachedImage(url, store: NoImageStore())),
      isFalse,
    );
  });

  group('identidad del proveedor', () {
    test('dos proveedores de la misma URL son la misma clave', () {
      // De esto depende que Flutter deduplique: dos fichas del mismo jugador
      // en pantalla no deben decodificar la imagen dos veces.
      expect(
        CachedImage(url, store: store),
        equals(CachedImage(url, store: store)),
      );
    });

    test('URLs distintas son claves distintas', () {
      expect(
        CachedImage(url, store: store),
        isNot(CachedImage('$url?v=2', store: store)),
      );
    });

    test('mismo URL con otro almacén es otra clave', () {
      // Si fueran iguales, el segundo recibiría lo resuelto por el primero y
      // su almacén no llegaría a consultarse nunca.
      expect(
        CachedImage(url, store: store),
        isNot(const CachedImage(url, store: NoImageStore())),
      );
    });
  });
}
