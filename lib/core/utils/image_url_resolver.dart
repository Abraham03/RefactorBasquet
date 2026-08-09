// lib/core/utils/image_url_resolver.dart
import '../constants/api_constants.dart';

/// Punto único de resolución de rutas de imagen provenientes del backend.
///
/// El backend entrega rutas relativas (`../uploads/logos/x.png`) que hay que
/// convertir en URLs absolutas. Es **agnóstico al formato**: nunca inspecciona
/// la extensión, así que una migración de `.png` a `.webp` no lo afecta.
class ImageUrlResolver {
  const ImageUrlResolver._();

  /// Devuelve una URL absoluta, o `null` si no hay ruta utilizable.
  ///
  /// Es idempotente: una URL ya absoluta se devuelve intacta, de modo que
  /// resolver dos veces (UI y luego generador de PDF) es inofensivo.
  static String? resolve(String? rawPath) {
    final path = rawPath?.trim();
    if (path == null || path.isEmpty) return null;

    final lower = path.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return path;
    if (lower.startsWith('data:')) return path;

    var clean = path.replaceAll('../', '').replaceAll('./', '');
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    if (clean.isEmpty) return null;

    // `Uri.resolve` codifica espacios y acentos; concatenar strings no lo hace.
    return Uri.parse(kServerBaseUrl).resolve(Uri.encodeFull(clean)).toString();
  }

  /// Variante para APIs que exigen `String` no nulo (devuelve '' si no hay ruta).
  static String resolveOrEmpty(String? rawPath) => resolve(rawPath) ?? '';
}
