import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:myapp/core/network/api_actions.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/core/network/result.dart';

/// Partido: sincronización del acta, consulta de eventos y correcciones.
class MatchApi {
  MatchApi(this._client);

  final ApiClient _client;

  // --- Subida del acta ---

  Future<Result<void>> syncMatchData(Map<String, dynamic> matchPayload) {
    return _client.post(
      ApiActions.syncMatch,
      body: matchPayload,
      decode: (_) {},
    );
  }

  /// Igual que [syncMatchData] pero adjuntando el PDF del acta.
  ///
  /// El backend espera el JSON en el campo `data` y el archivo en `pdf_report`.
  Future<Result<void>> syncMatchDataMultipart({
    required Map<String, dynamic> matchData,
    required Uint8List? pdfBytes,
  }) {
    return _client.multipart(
      ApiActions.syncMatch,
      fields: {'data': jsonEncode(matchData)},
      files: [
        if (pdfBytes != null)
          http.MultipartFile.fromBytes(
            'pdf_report',
            pdfBytes,
            filename: 'match_report.pdf',
            contentType: MediaType('application', 'pdf'),
          ),
      ],
      decode: (_) {},
    );
  }

  // --- Correcciones ---

  Future<Result<String?>> updateMatchAttendance({
    required String matchId,
    required List<Map<String, dynamic>> attendance,
  }) {
    return _client.postEnvelope(
      ApiActions.updateMatchAttendance,
      body: {'match_id': matchId, 'attendance': attendance},
      decode: (envelope) => envelope['message']?.toString(),
    );
  }

  /// Cambia el resultado (inasistencia, observaciones, firma) y sube el acta.
  ///
  /// Nótese que el PDF va **sin** `contentType` explícito, a diferencia de
  /// [syncMatchDataMultipart]: así lo hace el código actual y el golden lo tiene
  /// congelado como `application/octet-stream`.
  Future<Result<String?>> updateMatchOutcome({
    required String matchId,
    required String forfeitStatus,
    required String observaciones,
    String? signatureBase64,
    required int scoreA,
    required int scoreB,
    String? tournamentId,
    Uint8List? pdfBytes,
  }) {
    return _client.multipartEnvelope(
      ApiActions.updateMatchOutcome,
      fields: {
        'data': jsonEncode({
          'match_id': matchId,
          'forfeit_status': forfeitStatus,
          'observaciones': observaciones,
          'signature_data': signatureBase64,
          'score_a': scoreA,
          'score_b': scoreB,
          'tournament_id': tournamentId,
        }),
      },
      files: [
        if (pdfBytes != null)
          http.MultipartFile.fromBytes(
            'pdf_report',
            pdfBytes,
            filename: 'match_$matchId.pdf',
          ),
      ],
      decode: (envelope) => envelope['message']?.toString(),
    );
  }

  // --- Consultas para hidratar un partido jugado en otro dispositivo ---

  Future<Result<({int scoreA, int scoreB})>> getRealScores(String matchId) {
    return _client.get(
      ApiActions.getRealScores,
      query: {'match_id': matchId},
      decode: (raw) {
        final data = raw! as Map;
        // `.toInt()` sobre num normaliza por si el JSON lo serializa como
        // decimal y evita un error de cast.
        return (
          scoreA: (data['real_score_a'] as num).toInt(),
          scoreB: (data['real_score_b'] as num).toInt(),
        );
      },
    );
  }

  Future<Result<Map<String, dynamic>>> getMatchDetails(String matchId) {
    return _client.get(
      ApiActions.getMatchDetails,
      query: {'match_id': matchId},
      decode: (data) => (data! as Map).cast<String, dynamic>(),
    );
  }

  Future<Result<List<Map<String, dynamic>>>> getMatchEvents(String matchId) {
    return _client.get(
      ApiActions.getMatchEvents,
      query: {'match_id': matchId},
      decode: (data) => (data! as List).cast<Map<String, dynamic>>(),
    );
  }

  Future<Result<List<Map<String, dynamic>>>> getMatchRosters(String matchId) {
    return _client.get(
      ApiActions.getMatchRosters,
      query: {'match_id': matchId},
      decode: (data) => (data! as List).cast<Map<String, dynamic>>(),
    );
  }
}
