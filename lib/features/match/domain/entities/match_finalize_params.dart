import 'dart:typed_data';

/// Datos necesarios para generar el acta y finalizar un partido.
/// Se arma desde el widget (o desde donde sea) y se pasa al MatchFinalizer,
/// de modo que el finalizer no dependa de la UI.
class MatchFinalizeParams {
  final int tournamentId;
  final String teamAName;
  final String teamBName;
  final String tournamentName;
  final String categoryName;
  final String tournamentLogoUrl;
  final String venueName;
  final String mainReferee;
  final String auxReferee;
  final String scorekeeper;
  final String coachA;
  final String coachB;
  final int? captainAId;
  final int? captainBId;
  final DateTime? matchDate;

  const MatchFinalizeParams({
    required this.tournamentId,
    required this.teamAName,
    required this.teamBName,
    required this.tournamentName,
    required this.categoryName,
    required this.tournamentLogoUrl,
    required this.venueName,
    required this.mainReferee,
    required this.auxReferee,
    required this.scorekeeper,
    required this.coachA,
    required this.coachB,
    required this.captainAId,
    required this.captainBId,
    required this.matchDate,
  });
}

/// Resultado de finalizar un partido.
class FinalizeResult {
  /// True si se sincronizó a la nube; false si quedó guardado solo localmente.
  final bool synced;

  /// Bytes del PDF generado (para previsualizar o compartir).
  final Uint8List pdfBytes;

  const FinalizeResult({required this.synced, required this.pdfBytes});
}