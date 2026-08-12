import 'dart:async';
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'package:myapp/shared/services/image_store.dart';

/// Imagen de red con caché **en disco**.
///
/// `Image.network` solo guarda en el `ImageCache` de memoria, que muere con el
/// proceso: sin cobertura, las fotos de los jugadores y los escudos de los
/// equipos caían siempre al placeholder, aunque se hubieran visto mil veces.
///
/// Se implementa como [ImageProvider] y no como un `FutureBuilder` con
/// `Image.memory` para no perder lo que Flutter ya hace bien: deduplicar por
/// clave, compartir el decodificado entre widgets y respetar `cacheWidth`.
///
/// La primera vez que se ve una imagen se baja y se guarda; a partir de ahí
/// sale del disco. Es deliberadamente perezoso: precargar el catálogo entero
/// serían cientos de descargas para fotos que quizá nadie abra.
@immutable
class CachedImage extends ImageProvider<CachedImage> {
  const CachedImage(this.url, {required this.store, this.scale = 1.0});

  /// URL ya resuelta a absoluta.
  final String url;

  final ImageStore store;

  final double scale;

  /// Cliente HTTP. Es sustituible para los tests; en la app nadie lo toca.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  /// Una foto que tarda más que esto no vale la espera en una pantalla.
  static const Duration timeout = Duration(seconds: 10);

  @override
  Future<CachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedImage>(this);

  @override
  ImageStreamCompleter loadImage(CachedImage key, ImageDecoderCallback decode) {
    // El progreso se emite de verdad, byte a byte: es lo que alimenta el
    // `loadingBuilder` del widget. Un acierto de caché no emite ninguno, así
    // que la imagen de disco aparece sin spinner, que es lo correcto.
    final chunks = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _decode(key, decode, chunks),
      chunkEvents: chunks.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => [ErrorDescription('URL: ${key.url}')],
    );
  }

  Future<ui.Codec> _decode(
    CachedImage key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunks,
  ) async {
    try {
      final bytes = await _bytes(key, chunks);
      if (bytes == null || bytes.isEmpty) {
        // Que falle el completer es lo que dispara el `errorBuilder` del
        // widget, y con él el placeholder. Sin excepción se quedaría en blanco.
        throw StateError('No hay imagen para ${key.url}');
      }
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } finally {
      await chunks.close();
    }
  }

  Future<Uint8List?> _bytes(
    CachedImage key,
    StreamController<ImageChunkEvent> chunks,
  ) async {
    final cached = await key.store.read(key.url);
    if (cached != null) return cached;

    final client = clientFactory();
    try {
      final request = http.Request('GET', Uri.parse(key.url));
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        debugPrint('[CachedImage] HTTP ${response.statusCode} en ${key.url}');
        return null;
      }

      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        buffer.add(chunk);
        chunks.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: buffer.length,
            expectedTotalBytes: response.contentLength,
          ),
        );
      }
      if (buffer.isEmpty) return null;

      final bytes = buffer.takeBytes();
      await key.store.write(key.url, bytes);
      return bytes;
    } catch (e) {
      // Sin red y sin caché no hay imagen. No es un error de la app: es el
      // caso normal del gimnasio sin señal, y el placeholder lo cubre.
      debugPrint('[CachedImage] no se pudo obtener ${key.url} -> $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// El almacén entra en la identidad, no solo la URL.
  ///
  /// Flutter cachea el decodificado por esta clave: si dos proveedores de la
  /// misma URL con almacenes distintos fueran iguales, el segundo recibiría
  /// lo que resolvió el primero y su almacén nunca se consultaría. En la app
  /// hay un almacén por tipo de imagen y son únicos, así que la comparación
  /// por identidad basta.
  @override
  bool operator ==(Object other) =>
      other is CachedImage &&
      other.url == url &&
      other.scale == scale &&
      identical(other.store, store);

  @override
  int get hashCode => Object.hash(url, scale, identityHashCode(store));

  @override
  String toString() => 'CachedImage("$url", scale: $scale)';
}
