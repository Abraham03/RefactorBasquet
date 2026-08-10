import 'package:myapp/features/match/domain/entities/referee_signatures.dart';

/// Lo que el dominio necesita saber de los oficiales.
///
/// **Por qué existe esta interfaz y no las de los demás repositorios:** aquí
/// hay una inversión real que hacer. `MatchFinalizer` vive en `domain/` y
/// dependía de `OfficialRepository`, que es `data/` y abre drift. Con este
/// contrato, el dominio declara *qué* necesita y `data/` lo cumple (DIP).
///
/// Los **datasources** (`TeamApi`, `MatchApi`, …) NO llevan interfaz a
/// propósito: ya reciben un `ApiClient` inyectable, así que un test los
/// sustituye con `MockClient` sin necesidad de abstraerlos. Una interfaz con
/// una sola implementación y ningún sustituto es ceremonia, no diseño.
abstract interface class OfficialRepositoryContract {
  /// Firmas del árbitro principal y auxiliar, ya decodificadas de base64.
  Future<RefereeSignatures> getRefereeSignatures({
    required String mainRefereeName,
    required String auxRefereeName,
  });
}
