/// Jerarquía sellada de fallos de la app.
///
/// Reemplaza tres convenciones incompatibles que convivían en `ApiService`:
///   - `Future<bool>` con `catch → return false`, que **destruía la causa**:
///     el llamador no podía distinguir "sin internet" de "el servidor rechazó
///     la petición" de "el JSON venía mal".
///   - `throw Exception('...: $e')`, que anidaba excepciones y obligaba a las
///     pantallas a limpiar el prefijo con `replaceFirst('Exception: ', '')`.
///   - `return []` / `return {}`, indistinguible de "no hay datos".
///
/// Al ser `sealed`, el `switch` exhaustivo de Dart 3 obliga a contemplar todos
/// los casos: si mañana se agrega uno nuevo, el compilador señala cada sitio
/// que hay que actualizar.
library;

sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// Mensaje apto para mostrar al usuario.
  final String message;

  /// Error original, para diagnóstico. Nunca se muestra en la UI.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// No se pudo hablar con el servidor: DNS, socket, TLS, red caída.
final class NetworkException extends AppException {
  const NetworkException({
    String message = 'Sin conexión: esta acción requiere internet.',
    super.cause,
  }) : super(message);
}

/// La petición tardó más de lo permitido.
///
/// Se llama `Request...` y no `TimeoutException` a propósito: ese nombre ya lo
/// ocupa `dart:async` y la colisión obligaría a poner prefijos de librería en
/// cada `catch` de la capa de red.
final class RequestTimeoutException extends AppException {
  const RequestTimeoutException({
    String message = 'El servidor tardó demasiado en responder.',
    super.cause,
  }) : super(message);
}

/// El servidor respondió, pero con un código HTTP que no es 200 ni 201.
final class HttpStatusException extends AppException {
  const HttpStatusException(this.statusCode, {String? message, super.cause})
    : super(
        message ?? 'El servidor rechazó la solicitud (código $statusCode).',
      );

  final int statusCode;
}

/// El servidor respondió 200 con `status != 'success'`.
///
/// Es un rechazo de **regla de negocio**, no un fallo técnico: el `message`
/// viene del backend y suele ser accionable ("ya hay partidos jugados").
final class ApiBusinessException extends AppException {
  const ApiBusinessException(super.message, {super.cause});
}

/// La respuesta no era el JSON esperado.
final class ParseException extends AppException {
  const ParseException({
    String message = 'El servidor devolvió una respuesta inesperada.',
    super.cause,
  }) : super(message);
}
