import 'dart:convert';
import 'dart:typed_data';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/reports/data/pdf_generator.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';

/// Cambia el desenlace de un partido finalizado: aplica la regla de marcador,
/// regenera el PDF y sincroniza los 5 campos. SRP: orquesta, no decide la
/// regla (controller) ni persiste (API/DAO).
class OutcomeChanger {
  final MatchApi _api;
  OutcomeChanger(this._api);

  Future<Result<String?>> change({
    required MatchGameController controller,
    required String newOutcome, // 'NONE','TEAM_A','TEAM_B','BOTH'
    Uint8List? signature,
    String? observaciones,
    required OutcomePdfParams pdfParams,
  }) async {
    // 1. Aplicar la regla; el método retorna el estado nuevo (encapsulamiento).
    final updated = await controller.changeOutcome(
      newOutcome,
      _api,
      signature: signature,
      observaciones: observaciones,
    );

    // 2. Regenerar el PDF. El ganador se deriva solo del nuevo marcador.
    final pdfBytes = await PdfGenerator.generateBytes(
      updated,
      pdfParams.teamAName,
      pdfParams.teamBName,
      tournamentName: pdfParams.tournamentName,
      categoryName: pdfParams.categoryName,
      tournamentLogoUrl: pdfParams.tournamentLogoUrl,
      refereeLogoUrl: pdfParams.refereeLogoUrl,
      venueName: pdfParams.venueName,
      mainReferee: pdfParams.mainReferee,
      auxReferee: pdfParams.auxReferee,
      scorekeeper: pdfParams.scorekeeper,
      coachA: pdfParams.coachA,
      coachB: pdfParams.coachB,
      captainAId: pdfParams.captainAId,
      captainBId: pdfParams.captainBId,
      protestSignature: signature,
      matchDate: pdfParams.matchDate,
      mainRefSignature: pdfParams.mainRefSignature,
      auxRefSignature: pdfParams.auxRefSignature,
    );

    // 3. Sincronizar los 5 campos + PDF por el endpoint estrecho.
    return _api.updateMatchOutcome(
      matchId: updated.matchId,
      forfeitStatus: updated.forfeitStatus,
      observaciones: updated.observaciones,
      signatureBase64: signature == null ? null : base64Encode(signature),
      scoreA: updated.scoreA,
      scoreB: updated.scoreB,
      tournamentId: pdfParams.tournamentId,
      pdfBytes: pdfBytes,
    );
  }
}

/// Datos del acta necesarios para regenerar el PDF. Se arman al reabrir el
/// partido finalizado (desde la fila `matches` local + fixture del calendario).
class OutcomePdfParams {
  final String teamAName, teamBName, tournamentName, categoryName;
  final String tournamentLogoUrl, refereeLogoUrl, venueName;
  final String mainReferee, auxReferee, scorekeeper, coachA, coachB;
  final int? captainAId, captainBId;
  final DateTime? matchDate;
  final Uint8List? mainRefSignature, auxRefSignature;
  final String? tournamentId;

  const OutcomePdfParams({
    required this.teamAName,
    required this.teamBName,
    this.tournamentName = "",
    this.categoryName = "",
    this.tournamentLogoUrl = "",
    this.refereeLogoUrl = "",
    this.venueName = "",
    this.mainReferee = "",
    this.auxReferee = "",
    this.scorekeeper = "",
    this.coachA = "",
    this.coachB = "",
    this.captainAId,
    this.captainBId,
    this.matchDate,
    this.mainRefSignature,
    this.auxRefSignature,
    this.tournamentId,
  });
}
