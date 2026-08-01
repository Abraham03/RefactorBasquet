import 'package:flutter/foundation.dart';
import 'package:flutter_presentation_display/flutter_presentation_display.dart';

/// Gestiona la pantalla externa (HDMI/AnyCast) de forma independiente del
/// ciclo de vida de cualquier widget. Singleton porque solo hay una pantalla
/// física y un único estado "está mostrándose o no".
///
/// SRP: su única responsabilidad es encender/apagar/mantener el scoreboard
/// externo. La pantalla del partido lo USA, no lo POSEE: por eso salir del
/// partido ya no apaga la TV.
class ExternalDisplayService {
  ExternalDisplayService._();
  static final ExternalDisplayService instance = ExternalDisplayService._();

  final FlutterPresentationDisplay _manager = FlutterPresentationDisplay();

  /// Si el scoreboard ya está activo en la pantalla externa. Evita el ciclo
  /// hide+show que causaba el fallo de timing al reanudar.
  bool _isShowing = false;
  bool _operationInProgress = false; // ← evita llamadas concurrentes
  bool get isShowing => _isShowing;

  Future<void> showScoreboard() async {
    // Guard inmediato: si ya está mostrándose o hay una operación en curso,
    // salir sin tocar el canal nativo (evita cuelgues por llamadas concurrentes).
    if (_isShowing || _operationInProgress) return;
    _operationInProgress = true;
    try {
      final displays = await _manager.getDisplays();
      if (displays != null && displays.length > 1) {
        final displayId = displays[1].displayId;
        if (displayId != null) {
          await _manager.showSecondaryDisplay(
            displayId: displayId,
            routerName: "presentation_scoreboard",
          );
          _isShowing = true;
          debugPrint("ExternalDisplay: scoreboard mostrado en $displayId");
        }
      }
    } catch (e) {
      debugPrint("ExternalDisplay: no se pudo mostrar: $e");
    } finally {
      _operationInProgress = false;
    }
  }

  /// Apaga el scoreboard. Solo debe llamarse cuando de verdad se deja de usar
  /// el marcador, no al navegar entre pantallas.
  Future<void> hideScoreboard() async {
    if (!_isShowing || _operationInProgress) return;
    _operationInProgress = true;
    try {
      final displays = await _manager.getDisplays();
      if (displays != null && displays.length > 1) {
        final displayId = displays[1].displayId;
        if (displayId != null) {
          await _manager.hideSecondaryDisplay(displayId: displayId);
          debugPrint("ExternalDisplay: scoreboard ocultado");
        }
      }
    } catch (e) {
      debugPrint("ExternalDisplay: error al ocultar: $e");
    } finally {
      _isShowing = false;
      _operationInProgress = false;
    }
  }
}