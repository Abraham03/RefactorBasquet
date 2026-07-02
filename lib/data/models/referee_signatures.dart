import 'dart:typed_data';

/// Firmas de los árbitros ya decodificadas (base64 → bytes), listas para
/// pasar al generador de PDF. Independiente de la UI y de la BD.
class RefereeSignatures {
  final Uint8List? main;
  final Uint8List? aux;

  const RefereeSignatures({this.main, this.aux});
}