import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/database/app_database.dart';
import '../../core/service/api_service.dart';
import '../../core/utils/pdf_generator.dart';
import '../../data/repositories/official_repository.dart';
import '../../data/models/match_finalize_params.dart';
import '../../logic/match_game_controller.dart';

/// Orquesta el cierre de un partido: reconcilia jugadores offline, recupera
/// firmas y logo, genera el acta en PDF, sincroniza a la nube y marca el
/// partido y su fixture como FINISHED.
///
/// No conoce la UI: no muestra loaders ni SnackBars ni navega. Devuelve un
/// [FinalizeResult] y la pantalla decide cómo presentarlo. Esto lo hace
/// testeable y evita duplicar la orquestación en cada punto de finalización.
class MatchFinalizer {
  final AppDatabase _db;
  final ApiService _api;
  final OfficialRepository _officialRepo;
  final MatchGameController _controller;

  MatchFinalizer(this._db, this._api, this._officialRepo, this._controller);

  Future<FinalizeResult> finalize({
    required MatchState state,
    required MatchFinalizeParams params,
    Uint8List? protestSignature,
  }) async {
    // 1. Reconciliar jugadores offline (si no hay red, se ignora y se
    //    sincronizará después; el jugador queda con ID negativo local).
    try {
      await _controller.reconcileOfflinePlayers(_api);
    } catch (e) {
      debugPrint("Modo Offline Activo: Se sincronizará después.");
    }

    // 2. Logo del árbitro (vive en el torneo).
    final tournamentObj = await (_db.select(_db.tournaments)
          ..where((t) => t.id.equals(params.tournamentId.toString())))
        .getSingleOrNull();
    final String refereeLogoUrl = tournamentObj?.refereeLogoUrl ?? "";

    // 3. Firmas de árbitros (recuperadas y decodificadas por el repositorio).
    final signatures = await _officialRepo.getRefereeSignatures(
      mainRefereeName: params.mainReferee,
      auxRefereeName: params.auxReferee,
    );

    // 4. Generar el PDF del acta.
    final pdfBytes = await PdfGenerator.generateBytes(
      state,
      params.teamAName,
      params.teamBName,
      tournamentName: params.tournamentName,
      categoryName: params.categoryName,
      tournamentLogoUrl: params.tournamentLogoUrl,
      refereeLogoUrl: refereeLogoUrl,
      venueName: params.venueName,
      mainReferee: params.mainReferee,
      auxReferee: params.auxReferee,
      scorekeeper: params.scorekeeper,
      coachA: params.coachA,
      coachB: params.coachB,
      captainAId: params.captainAId,
      captainBId: params.captainBId,
      protestSignature: protestSignature,
      matchDate: params.matchDate ?? DateTime.now(),
      mainRefSignature: signatures.main,
      auxRefSignature: signatures.aux,
    );

    // 5. Finalizar y sincronizar a la nube.
    final bool synced = await _controller.finalizeAndSync(
      _api,
      protestSignature,
      pdfBytes,
      params.teamAName,
      params.teamBName,
    );

    // 6. Marcar partido y fixture como FINISHED localmente.
    await (_db.update(_db.matches)..where((tbl) => tbl.id.equals(state.matchId)))
        .write(const MatchesCompanion(status: Value('FINISHED')));

    if (state.fixtureId != null) {
      await (_db.update(_db.fixtures)..where((tbl) => tbl.id.equals(state.fixtureId!)))
          .write(FixturesCompanion(
        status: const Value('FINISHED'),
        scoreA: Value(state.scoreA),
        scoreB: Value(state.scoreB),
      ));
    }

    return FinalizeResult(synced: synced, pdfBytes: pdfBytes);
  }
}