// `Uint8List` es de `dart:typed_data` y `log` de `dart:developer`: ninguno
// necesita Flutter. Antes se tiraba de `flutter/foundation` por costumbre, y
// eso ataba el dominio al framework (regla 3 del plan).
import 'dart:developer';
import 'dart:typed_data';

import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/teams/data/datasources/team_api.dart';
import 'package:myapp/features/reports/data/pdf_generator.dart';
import 'package:myapp/features/match/domain/repositories/official_repository_contract.dart';
import 'package:myapp/features/match/domain/entities/match_finalize_params.dart';
import 'package:myapp/features/match/domain/repositories/match_closing_repository.dart';
import 'package:myapp/features/match/domain/repositories/match_finalization_port.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/match/domain/engines/game_clock.dart';

/// Orquesta el cierre de un partido: reconcilia jugadores offline, recupera
/// firmas y logo, genera el acta en PDF, sincroniza a la nube y marca el
/// partido y su fixture como FINISHED.
///
/// No conoce la UI: no muestra loaders ni SnackBars ni navega. Devuelve un
/// [FinalizeResult] y la pantalla decide cómo presentarlo. Esto lo hace
/// testeable y evita duplicar la orquestación en cada punto de finalización.
class MatchFinalizer {
  final MatchClosingRepository _closing;
  final MatchApi _matchApi;
  final TeamApi _teamApi;
  final OfficialRepositoryContract _officialRepo;
  final MatchFinalizationPort _controller;

  MatchFinalizer(
    this._closing,
    this._matchApi,
    this._teamApi,
    this._officialRepo,
    this._controller,
  );

  Future<FinalizeResult> finalize({
    required MatchState state,
    required MatchFinalizeParams params,
    Uint8List? protestSignature,
  }) async {
    // 1. Reconciliar jugadores offline (si no hay red, se ignora y se
    //    sincronizará después; el jugador queda con ID negativo local).
    try {
      await _controller.reconcileOfflinePlayers(_teamApi);
    } catch (e) {
      log(
        'Modo offline: los jugadores locales se sincronizarán después.',
        name: 'MatchFinalizer',
        error: e,
      );
    }

    // 2. El partido se cierra: quien no gastó su tiempo fuera de la segunda
    //    mitad lo pierde, porque ya no hay ocasión de pedirlo. Se aplica
    //    sobre el estado que va al acta.
    //
    //    En vivo esto ya lo hace el reloj al cruzar los dos minutos, pero
    //    solo si el reloj llega a cruzarlos: un partido cerrado tras ajustar
    //    el tiempo a mano se quedaba sin la marca. No afecta al payload del
    //    backend, que no lleva los tiempos fuera —los deriva de los
    //    eventos— así que el contrato queda intacto.
    final actaState = state.currentPeriod >= GameClockRules.lastPeriod
        ? _controller.burnUnusedTimeouts()
        : state;

    // 3. Logo del árbitro (vive en el torneo).
    final refereeLogoUrl = await _closing.refereeLogoUrl(
      params.tournamentId.toString(),
    );

    // 4. Firmas de árbitros (recuperadas y decodificadas por el repositorio).
    final signatures = await _officialRepo.getRefereeSignatures(
      mainRefereeName: params.mainReferee,
      auxRefereeName: params.auxReferee,
    );

    // 5. Generar el PDF del acta.
    final pdfBytes = await PdfGenerator.generateBytes(
      actaState,
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

    // 6. Finalizar y sincronizar a la nube.
    final bool synced = await _controller.finalizeAndSync(
      _matchApi,
      protestSignature,
      pdfBytes,
      params.teamAName,
      params.teamBName,
    );

    // 7. Marcar partido y fixture como FINISHED localmente.
    await _closing.markFinished(
      matchId: state.matchId,
      fixtureId: state.fixtureId,
      scoreA: state.scoreA,
      scoreB: state.scoreB,
    );

    return FinalizeResult(synced: synced, pdfBytes: pdfBytes);
  }
}
