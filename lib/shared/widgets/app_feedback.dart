import 'package:flutter/material.dart';

/// Feedback visual estandarizado para toda la app.
/// Reemplaza los ~50 bloques de SnackBar repetidos (Row + Icon + Text +
/// colores + shape + margin) por una sola fuente de verdad. Cualquier
/// ajuste de estilo (color, forma, duración) se hace aquí una vez.
/// Uso:
///   context.showSuccess("Torneo creado");
///   context.showError("Sin conexión");
///   context.showInfo("Reporte actualizado");
///   final ctrl = context.showLoading("Subiendo...");   se queda abierto
///   ctrl.close();                                       lo cierras tú
extension AppFeedback on BuildContext {
  void showSuccess(String message) =>
      _show(message, _FeedbackKind.success);

  void showError(String message) =>
      _show(message, _FeedbackKind.error);

  void showInfo(String message) =>
      _show(message, _FeedbackKind.info);

  void showWarning(String message) =>
      _show(message, _FeedbackKind.warning);

  /// Muestra un SnackBar persistente con spinner (operaciones largas).
  /// Devuelve un controlador para cerrarlo manualmente al terminar.
  LoadingSnackBar showLoading(String message) {
    final messenger = ScaffoldMessenger.of(this);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        backgroundColor: Colors.blueGrey.shade800,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(minutes: 5), // largo; lo cerramos a mano
      ),
    );
    return LoadingSnackBar._(messenger, controller);
  }

  void _show(String message, _FeedbackKind kind) {
    final messenger = ScaffoldMessenger.of(this);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(kind.icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        backgroundColor: kind.color,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// Controlador para cerrar un SnackBar de carga.
class LoadingSnackBar {
  final ScaffoldMessengerState _messenger;
  // ignore: unused_field
  final ScaffoldFeatureController _controller;

  LoadingSnackBar._(this._messenger, this._controller);

  void close() => _messenger.hideCurrentSnackBar();
}

enum _FeedbackKind { success, error, info, warning }

extension on _FeedbackKind {
  Color get color {
    switch (this) {
      case _FeedbackKind.success:
        return Colors.green.shade700;
      case _FeedbackKind.error:
        return Colors.redAccent;
      case _FeedbackKind.info:
        return Colors.blueGrey.shade800;
      case _FeedbackKind.warning:
        return Colors.orange.shade800;
    }
  }

  IconData get icon {
    switch (this) {
      case _FeedbackKind.success:
        return Icons.check_circle;
      case _FeedbackKind.error:
        return Icons.error_outline;
      case _FeedbackKind.info:
        return Icons.info_outline;
      case _FeedbackKind.warning:
        return Icons.warning_amber_rounded;
    }
  }
}