// lib/core/service/image_loader_service.dart
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import 'package:myapp/core/utils/image_format.dart';
import 'package:myapp/core/utils/image_url_resolver.dart';
import 'package:myapp/shared/services/image_store.dart';

/// Fallo al obtener o decodificar una imagen remota destinada al PDF.
/// Lleva siempre la URL para que el log sea accionable.
class ImageLoadException implements Exception {
  final String url;
  final String reason;
  const ImageLoadException(this.url, this.reason);

  @override
  String toString() => 'ImageLoadException: $reason ($url)';
}

/// Carga imágenes de red para embeberlas en el PDF.
///
/// Sustituye a `networkImage()` de `printing` por tres razones:
///  - valida `statusCode` (una página de error 404 ya no llega como "bytes de imagen");
///  - decodifica fuera del isolate de UI, evitando el jank del decode VP8 de WebP;
///  - reescala al tamaño de dibujo, en vez de embeber el ráster a resolución completa.
class PdfImageLoader {
  const PdfImageLoader._();

  /// Descarga y prepara la imagen. Devuelve `null` sólo si no hay ruta.
  /// Cualquier otro fallo lanza [ImageLoadException] o la excepción de red.
  ///
  /// [targetWidth] es el ancho máximo en píxeles del ráster embebido; los logos
  /// se dibujan a 53-60 pt, así que 160 px cubre densidades altas de sobra.
  ///
  /// Con [cache] la red deja de ser obligatoria: si la URL ya se bajó alguna
  /// vez, el acta sale con logos **sin cobertura**. Lo que se guarda son los
  /// bytes ya preparados, no la respuesta cruda, así que el reescalado se paga
  /// una sola vez. La clave es la URL resuelta, y por eso [targetWidth] no
  /// debería variar entre llamadas para una misma URL.
  static Future<pw.ImageProvider?> fromNetwork(
    String? rawUrl, {
    int targetWidth = 160,
    Duration timeout = const Duration(seconds: 8),
    ImageStore? cache,
  }) async {
    final url = ImageUrlResolver.resolve(rawUrl);
    if (url == null) return null;

    if (cache != null) {
      final hit = await cache.read(url);
      if (hit != null) return pw.MemoryImage(hit);
    }

    final prepared = await _fetchPrepared(
      url,
      targetWidth: targetWidth,
      timeout: timeout,
    );
    if (cache != null) await cache.write(url, prepared);
    return pw.MemoryImage(prepared);
  }

  /// Baja [rawUrl] y la deja en [cache] sin construir la imagen del PDF.
  ///
  /// La usa la descarga del catálogo —que por definición ocurre con red— para
  /// dejar los logos listos antes de que haga falta generar un acta offline.
  /// Devuelve si quedó cacheada; nunca lanza, porque calentar la caché es un
  /// extra y no puede hacer fallar una sincronización que sí funcionó.
  ///
  /// Con [refresh] se vuelve a bajar aunque ya esté guardada. Hace falta
  /// porque el backend puede sustituir el escudo **sin cambiar la URL**, y
  /// entonces la caché serviría el viejo para siempre. La descarga del
  /// catálogo es el momento de resolverlo: es explícita y tiene red.
  static Future<bool> warmCache(
    String? rawUrl,
    ImageStore cache, {
    bool refresh = false,
    int targetWidth = 160,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final url = ImageUrlResolver.resolve(rawUrl);
    if (url == null) return false;
    if (!refresh && await cache.read(url) != null) return true;

    try {
      final prepared = await _fetchPrepared(
        url,
        targetWidth: targetWidth,
        timeout: timeout,
      );
      await cache.write(url, prepared);
      return true;
    } catch (e) {
      debugPrint('[PdfImageLoader] no se pudo precargar $url -> $e');
      return false;
    }
  }

  /// Los bytes listos para embeber: descargados, validados y reescalados.
  static Future<Uint8List> _fetchPrepared(
    String url, {
    required int targetWidth,
    required Duration timeout,
  }) async {
    final client = http.Client();
    final http.Response response;
    try {
      response = await client.get(Uri.parse(url)).timeout(timeout);
    } finally {
      client.close();
    }

    if (response.statusCode != 200) {
      throw ImageLoadException(url, 'HTTP ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw ImageLoadException(url, 'respuesta vacía');
    }

    switch (sniffImageFormat(bytes)) {
      // JPEG pasa tal cual: el PDF lo embebe como DCTDecode, sin re-encodear.
      case ImageFormatKind.jpeg:
        return bytes;

      // WebP/PNG/GIF/BMP: normalizamos a PNG en un isolate de fondo.
      case ImageFormatKind.webp:
      case ImageFormatKind.png:
      case ImageFormatKind.gif:
      case ImageFormatKind.bmp:
        try {
          final pngBytes = await compute(
            _decodeAndResizeToPng,
            (bytes: bytes, targetWidth: targetWidth),
          );
          return pngBytes;
        } catch (e) {
          throw ImageLoadException(url, 'no se pudo decodificar: $e');
        }

      case ImageFormatKind.unknown:
        throw ImageLoadException(
          url,
          'formato no reconocido (primeros bytes: ${_headHex(bytes)})',
        );
    }
  }

  static String _headHex(Uint8List bytes) {
    final n = bytes.length < 8 ? bytes.length : 8;
    return bytes
        .sublist(0, n)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }
}

/// Corre en un isolate de fondo. Devuelve `Uint8List` porque `img.Image` no
/// cruza isolates de forma barata; el PNG resultante además entra por la ruta
/// rápida de `PdfImage.file`.
Uint8List _decodeAndResizeToPng(({Uint8List bytes, int targetWidth}) req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) {
    throw Exception('decodeImage devolvió null');
  }

  final resized = decoded.width > req.targetWidth
      ? img.copyResize(
          decoded,
          width: req.targetWidth,
          interpolation: img.Interpolation.average,
        )
      : decoded;

  return img.encodePng(resized);
}
