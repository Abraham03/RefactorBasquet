// lib/core/utils/image_format.dart
import 'dart:typed_data';

/// Formatos de imagen que el pipeline reconoce.
enum ImageFormatKind { jpeg, png, gif, webp, bmp, unknown }

/// Identifica el formato por *magic bytes*, nunca por la extensión del archivo.
///
/// Necesario porque el backend puede servir WebP bajo cualquier nombre, y
/// porque una respuesta 404 en HTML llega como bytes que no son una imagen.
ImageFormatKind sniffImageFormat(Uint8List bytes) {
  if (bytes.length < 12) return ImageFormatKind.unknown;

  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return ImageFormatKind.jpeg;
  }

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (_matches(bytes, png, 0)) return ImageFormatKind.png;

  // GIF: "GIF87a" / "GIF89a"
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return ImageFormatKind.gif;
  }

  // WebP: "RIFF" en 0..3 + "WEBP" en 8..11
  const riff = [0x52, 0x49, 0x46, 0x46]; // R I F F
  const webp = [0x57, 0x45, 0x42, 0x50]; // W E B P
  if (_matches(bytes, riff, 0) && _matches(bytes, webp, 8)) {
    return ImageFormatKind.webp;
  }

  // BMP: "BM"
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return ImageFormatKind.bmp;

  return ImageFormatKind.unknown;
}

bool _matches(Uint8List bytes, List<int> signature, int offset) {
  if (bytes.length < offset + signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[offset + i] != signature[i]) return false;
  }
  return true;
}
