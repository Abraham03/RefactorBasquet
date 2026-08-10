import 'package:myapp/core/errors/app_exception.dart';

/// Resultado de una operación que puede fallar, sin usar excepciones como
/// control de flujo.
///
/// `sealed` + patrones de Dart 3: el `switch` es exhaustivo, así que olvidar
/// el caso de error es un error de compilación, no un bug en producción.
///
/// ```dart
/// switch (await api.crearSede(nombre, direccion)) {
///   case Ok(:final value):   context.showSuccess('Sede $value creada');
///   case Err(:final error):  context.showError(error.message);
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// `true` si la operación tuvo éxito.
  bool get isOk => this is Ok<T>;

  /// Valor si fue exitosa, `null` si no. Útil en el borde con código antiguo.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// Error si falló, `null` si no.
  AppException? get errorOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final error) => error,
  };

  /// Transforma el valor conservando el error.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok(transform(value)),
    Err<T>(:final error) => Err(error),
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final AppException error;
}

/// Resultado de una llamada al API que puede fallar con un mensaje.
///
/// **Obsoleto**: es el tipo previo a `Result<T>`. Se conserva como adaptador
/// mientras las pantallas migran (patrón Adapter, fase 3.2 del plan). No usar
/// en código nuevo.
class ApiResult {
  final bool success;
  final String? message;

  const ApiResult.ok([this.message]) : success = true;
  const ApiResult.fail(this.message) : success = false;

  /// Puente desde el mundo nuevo al antiguo, para no tener que migrar todas
  /// las pantallas de golpe.
  factory ApiResult.from(Result<String?> result) => switch (result) {
    Ok(:final value) => ApiResult.ok(value),
    Err(:final error) => ApiResult.fail(error.message),
  };
}
