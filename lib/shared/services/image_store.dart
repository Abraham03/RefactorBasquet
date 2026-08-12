import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Almacén local de imágenes remotas, indexado por su URL.
///
/// Nació por un fallo de campo con los escudos —un acta jugada sin cobertura
/// se cerraba sin ellos y ese PDF era el que se subía—, y sirve igual a las
/// fotos de los jugadores: la URL siempre está en la base local, lo que no
/// estaba eran los bytes.
abstract interface class ImageStore {
  /// Bytes cacheados de [url], o `null` si no hay nada guardado.
  Future<Uint8List?> read(String url);

  /// Guarda los bytes de [url]. Nunca lanza: un fallo de disco no puede
  /// tumbar ni la generación de un acta ni el pintado de una pantalla.
  Future<void> write(String url, Uint8List bytes);
}

/// Caché en disco, un archivo por URL.
class FileImageStore implements ImageStore {
  /// [root] se inyecta para los tests; en la app es el directorio de soporte,
  /// no el de documentos: esto es caché reconstruible, no las actas.
  ///
  /// [folderName] separa colecciones con políticas distintas: los escudos son
  /// dos y no deben caducar jamás, las fotos de jugadores son cientos.
  ///
  /// [maxBytes] a 0 significa **sin límite**, que es lo correcto para los
  /// escudos: recortarlos abriría justo el agujero que esta clase cierra.
  FileImageStore({
    Future<Directory> Function()? root,
    this.folderName = 'image_cache',
    this.maxBytes = 0,
  }) : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  final String folderName;

  /// Tamaño máximo de la carpeta. Al superarlo se borran los archivos más
  /// antiguos hasta bajar de [_trimTarget].
  final int maxBytes;

  /// Hasta dónde se vacía al recortar. Dejar margen evita recortar en cada
  /// escritura una vez alcanzado el tope.
  static const double _trimTarget = 0.8;

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
      debugPrint('[ImageStore] no se pudo leer $url -> $e');
      return null;
    }
  }

  @override
  Future<void> write(String url, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    try {
      final file = await _fileFor(url);
      // Escritura atómica: si la app muere a media escritura queda el `.tmp`
      // y no una imagen truncada que luego se intentaría decodificar.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      if (maxBytes > 0) await _trim();
    } catch (e) {
      debugPrint('[ImageStore] no se pudo guardar $url -> $e');
    }
  }

  /// Borra lo más antiguo hasta volver por debajo del tope.
  ///
  /// Se ordena por fecha de descarga, no de último uso: mantener un `atime`
  /// exacto obligaría a escribir en disco en **cada** lectura, y lo que se
  /// arriesga al equivocarse es una descarga de más, no un fallo.
  Future<void> _trim() async {
    final dir = await _ensureDir();
    final files = await dir
        .list()
        .where((e) => e is File && !e.path.endsWith('.tmp'))
        .cast<File>()
        .toList();

    final sizes = <File, int>{};
    var total = 0;
    for (final f in files) {
      final size = await f.length();
      sizes[f] = size;
      total += size;
    }
    if (total <= maxBytes) return;

    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );

    final target = (maxBytes * _trimTarget).round();
    for (final f in files) {
      if (total <= target) break;
      total -= sizes[f] ?? 0;
      await f.delete();
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
  /// dos equipos distintos pueden servir su `logo.png`, y colisionarían.
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
class NoImageStore implements ImageStore {
  const NoImageStore();

  @override
  Future<Uint8List?> read(String url) async => null;

  @override
  Future<void> write(String url, Uint8List bytes) async {}
}

/// Los dos almacenes de la app, con políticas distintas a propósito.
abstract final class AppImageStores {
  /// Escudos de torneo y de asociación: dos archivos, sin caducidad. Es lo
  /// que permite cerrar un acta sin cobertura con los logos puestos.
  static final ImageStore logos = FileImageStore(folderName: 'logo_cache');

  /// Fotos de jugadores y escudos de equipo que se pintan en pantalla. Aquí
  /// sí hay tope: son cientos y el catálogo las renueva temporada a temporada,
  /// así que sin límite la carpeta solo crecería.
  static final ImageStore photos = FileImageStore(
    folderName: 'photo_cache',
    maxBytes: 120 * 1024 * 1024,
  );
}
