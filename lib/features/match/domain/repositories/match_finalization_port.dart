import 'dart:typed_data';

import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/domain/entities/match_state.dart';
import 'package:myapp/features/teams/data/datasources/team_api.dart';

/// Lo que `MatchFinalizer` necesita del partido en curso para poder cerrarlo.
///
/// **Por qué existe:** `MatchFinalizer` vive en `domain/` y dependía de
/// `MatchGameController`, que es `presentation/`. La regla de dependencia justo
/// al revés: el dominio no puede necesitar la capa de UI para funcionar.
///
/// El puerto declara las dos únicas cosas que el finalizador pide, no los ~55
/// métodos del controller. Así se ve de un vistazo la superficie real del
/// acoplamiento, y un test puede darle un doble sin montar un partido entero.
abstract interface class MatchFinalizationPort {
  /// Sube los jugadores creados sin conexión y reemplaza sus ids temporales.
  ///
  /// Se hace antes de cerrar para que el acta no viaje con ids negativos, que
  /// el backend rechazaría.
  Future<void> reconcileOfflinePlayers(TeamApi api);

  /// Marca el partido como terminado y lo sincroniza con el acta en PDF.
  ///
  /// Devuelve `true` si la subida salió bien. Un `false` no es un error: el
  /// partido queda cerrado en local y pendiente de subir.
  Future<bool> finalizeAndSync(
    MatchApi api,
    Uint8List? signatureBytes,
    Uint8List? pdfBytes,
    String teamAName,
    String teamBName,
  );

  /// Aplica un cambio de desenlace (inasistencia, protesta) y devuelve el
  /// estado resultante.
  ///
  /// Lo usa `OutcomeChanger`, que tambien vive en `domain/` y dependia del
  /// controller por la misma razon.
  Future<MatchState> changeOutcome(
    String tipo,
    MatchApi api, {
    Uint8List? signature,
    String? observaciones,
  });
}
