import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../core/database/app_database.dart';
import '../models/referee_signatures.dart';

/// Acceso a datos de oficiales (árbitros).
///
/// Centraliza la recuperación y decodificación de firmas, que antes estaba
/// duplicada en _finishMatchProcess y _goToPdfPreview. Una sola fuente de
/// verdad: si mañana cambia el formato de la firma o el criterio de búsqueda,
/// se toca aquí una vez.
class OfficialRepository {
  final AppDatabase _db;

  OfficialRepository(this._db);

  /// Busca las firmas del árbitro principal y auxiliar por nombre y rol,
  /// y las devuelve ya decodificadas de base64 a bytes.
  Future<RefereeSignatures> getRefereeSignatures({
    required String mainRefereeName,
    required String auxRefereeName,
  }) async {
    final mainRefObj = await (_db.select(_db.officials)
          ..where((t) => t.name.equals(mainRefereeName))
          ..where((t) => t.role.equals('ARBITRO_PRINCIPAL')))
        .get()
        .then((list) => list.firstOrNull);

    final auxRefObj = await (_db.select(_db.officials)
          ..where((t) => t.name.equals(auxRefereeName))
          ..where((t) => t.role.equals('ARBITRO_AUXILIAR')))
        .get()
        .then((list) => list.firstOrNull);

    return RefereeSignatures(
      main: _decodeSignature(mainRefObj?.signatureData),
      aux: _decodeSignature(auxRefObj?.signatureData),
    );
  }

  Uint8List? _decodeSignature(String? base64Data) {
    if (base64Data == null || base64Data.isEmpty) return null;
    try {
      return base64Decode(base64Data);
    } catch (e) {
      debugPrint("Error decodificando firma: $e");
      return null;
    }
  }
}