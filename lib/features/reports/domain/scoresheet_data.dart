import 'dart:typed_data';

import 'package:myapp/features/match/domain/entities/match_state.dart';

/// Todo lo que hace falta para dibujar un acta.
///
/// **Por qué existe.** `_buildDocument` recibía estos 20 valores como
/// parámetros **posicionales**, y los tres métodos públicos
/// (`generateBytes`, `generateAndPreview`, `generateAndShare`) repetían cada
/// uno la misma llamada de 19 argumentos. Tres sitios donde cruzar
/// `mainReferee` con `auxReferee`, o `coachA` con `coachB`, compila sin una
/// sola queja y sale impreso en el acta que firma el árbitro.
///
/// Mismo patrón que `MatchRestoreSnapshot` en la Fase 5, y por la misma
/// razón: cuando una firma pasa de media docena de parámetros del mismo
/// tipo, el compilador deja de ayudarte.
class ScoresheetData {
  const ScoresheetData({
    required this.state,
    required this.teamAName,
    required this.teamBName,
    this.tournamentName = '',
    this.categoryName = '',
    this.tournamentLogoUrl = '',
    this.refereeLogoUrl = '',
    this.venueName = '',
    this.mainReferee = '',
    this.auxReferee = '',
    this.scorekeeper = '',
    this.coachA = '',
    this.coachB = '',
    this.captainAId,
    this.captainBId,
    this.protestSignature,
    this.matchDate,
    this.mainRefSignature,
    this.auxRefSignature,
  });

  final MatchState state;
  final String teamAName;
  final String teamBName;
  final String tournamentName;
  final String categoryName;
  final String tournamentLogoUrl;
  final String refereeLogoUrl;
  final String venueName;
  final String mainReferee;
  final String auxReferee;
  final String scorekeeper;
  final String coachA;
  final String coachB;
  final int? captainAId;
  final int? captainBId;

  /// Firma manuscrita de la protesta, si la hubo. PNG en crudo.
  final Uint8List? protestSignature;

  final DateTime? matchDate;
  final Uint8List? mainRefSignature;
  final Uint8List? auxRefSignature;
}
