import 'dart:convert';
import 'dart:typed_data';
import '../../core/network/api_result.dart';
import '../../core/service/api_service.dart';
import '../../core/utils/pdf_generator.dart';
import '../../logic/match_game_controller.dart';

/// Cambia el desenlace de un partido finalizado: aplica la regla, regenera
/// el PDF y sincroniza los 5 campos. SRP: orquesta, no decide la regla
/// (eso vive en el controller) ni persiste (eso vive en el DAO/API).
class OutcomeChanger {
  final ApiService _api;
  OutcomeChanger(this._api);

  Future<ApiResult> change({
    required MatchGameController controller,
    required MatchState state,
    required String newOutcome, // 'NONE','TEAM_A','TEAM_B','BOTH','PROTEST'
    Uint8List? signature,
    String? observaciones,
    required Map<String, dynamic> pdfParams, // datos para regenerar el acta
  }) async {
    // 1. Aplicar la regla de marcador en el estado.
   final updated = controller.changeOutcome(newOutcome, signature: signature, observaciones: observaciones);

    // 2. Regenerar el PDF (el ganador se deriva solo del nuevo marcador).
    final pdfBytes = await PdfGenerator.generateBytes(
      updated,
      pdfParams['teamAName'], pdfParams['teamBName'],
      // ... resto de params ...
    );

    // 3. Sincronizar los 5 campos + PDF vía el endpoint estrecho.
    return _api.updateMatchOutcome(
      matchId: updated.matchId,
      forfeitStatus: updated.forfeitStatus,
      observaciones: updated.observaciones,
      signatureBase64: signature == null ? null : base64Encode(signature),
      scoreA: updated.scoreA,
      scoreB: updated.scoreB,
      pdfBytes: pdfBytes,
    );
  }
}