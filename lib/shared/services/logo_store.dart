import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Almacén local de logos ya preparados para embeber en el acta.
///
/// Existe por un fallo de campo: un partido jugado sin cobertura se cerraba
/// **sin logos**, porque [PdfImageLoader] los bajaba de la red siempre. Y el
/// hueco no se recuperaba nunca, porque el PDF se guarda en disco al cerrar y
/// más tarde se sube ese mismo archivo, no uno regenerado.
///
/// La URL sigue estando disponible sin red —`tournaments.logo_url` se guarda
/// en la descarga del catálogo—; lo que faltaba eran los bytes.
abstract interface class LogoStore {
  /// Bytes cacheados de [url], o `null` si no hay nada guardado.
  Future<Uint8List?> read(String url);

  /// Guarda los bytes de [url]. Nunca lanza: un fallo de disco no puede
  /// tumbar la generación de un acta.
  Future<void> write(String url, Uint8List bytes);
}

/// Caché en disco, un archivo por URL.
///
/// Deliberadamente **sin caducidad ni límite de tamaño**: son un puñado de
/// logos de torneo y de asociación, y expirarlos abriría justo el agujero que
/// esta clase cierra —quedarse sin logo precisamente el día sin cobertura—.
/// Se sobrescriben solos cuando la URL del backend cambia.
class FileLogoStore implements LogoStore {
  /// [root] se inyecta para los tests; en la app es el directorio de soporte,
  /// no el de documentos: esto es caché reconstruible, no las actas.
  FileLogoStore({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  static const String folderName = 'logo_cache';

  Directory? _dir;

  @override
  Future<Uint8List?> read(String url) async {
    try {
      final file = await _fileFor(url);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      // Un archivo vacío es basura de una escritura interrumpida en una
      // versión anterior: se ignora y se vuelve a bajar.
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      debugPrint('[LogoStore] no se pudo leer $url -> $e');
      return null;
    }
  }

  @override
  Future<void> write(String url, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    try {
      final file = await _fileFor(url);
      // Escritura atómica: si la app muere a media escritura queda el `.tmp`
      // y no un logo truncado que el PDF intentaría decodificar.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[LogoStore] no se pudo guardar $url -> $e');
    }
  }

  Future<File> _fileFor(String url) async =>
      File(p.join((await _ensureDir()).path, fileNameFor(url)));

  Future<Directory> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;

    final dir = Directory(p.join((await _root()).path, folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Nombre determinista del archivo de [url].
  ///
  /// Se hashea la URL **completa** y no se reutiliza el nombre del servidor:
  /// dos torneos distintos pueden servir su `logo.png`, y colisionarían.
  @visibleForTesting
  static String fileNameFor(String url) => '${_fnv1a(url)}.img';

  /// FNV-1a de 64 bits. Se implementa aquí para no arrastrar `crypto` por un
  /// hash que solo tiene que ser estable y repartir bien, no ser criptográfico.
  static String _fnv1a(String input) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      // El desbordamiento envuelve solo en el int de 64 bits de la VM.
      hash *= 0x100000001b3;
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}

/// Sin caché. Para tests y para los llamadores que no deben tocar disco.
class NoLogoStore implements LogoStore {
  const NoLogoStore();

  @override
  Future<Uint8List?> read(String url) async => null;

  @override
  Future<void> write(String url, Uint8List bytes) async {}
}
