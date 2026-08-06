import 'dart:io';

/// Detecta si un error es de red (DNS, socket, timeout) y devuelve un
/// mensaje amigable para el usuario. Punto único de decisión (SRP):
/// las pantallas no interpretan excepciones de red, solo muestran el string.
class ConnectivityHelper {
  ConnectivityHelper._(); // No instanciable.

  /// Mensaje genérico cuando una acción online-only falla por red.
  static const _offlineMsg = 'Sin conexión: esta acción requiere internet.';

  /// Retorna true si el error es de conectividad (DNS, socket, timeout).
  static bool isNetworkError(Object error) {
    final msg = error.toString();
    return error is SocketException ||
        msg.contains('SocketException') ||
        msg.contains('ClientException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Connection refused') ||
        msg.contains('Connection reset') ||
        msg.contains('Network is unreachable') ||
        msg.contains('TimeoutException') ||
        msg.contains('HandshakeException');
  }

  /// Devuelve un mensaje de usuario legible:
  /// - Error de red → mensaje genérico amigable.
  /// - Otro error   → el [fallback] con el detalle técnico (debug).
  static String friendlyMessage(Object error, {String? fallback}) {
    if (isNetworkError(error)) return _offlineMsg;
    // Limpiar el prefijo "Exception: " que Dart agrega.
    final raw = fallback ?? error.toString();
    return raw.replaceFirst('Exception: ', '');
  }
}