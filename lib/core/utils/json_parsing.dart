/// Utilidades de coerción para el JSON del backend PHP.
///
/// MySQL vía PHP devuelve los enteros como string (`"7"`), así que por todo el
/// código había ~12 copias de `int.parse(json['id'].toString())`. Cuando el
/// valor llegaba `null` o vacío, esa expresión reventaba con un
/// `FormatException` sin contexto.
///
/// Adelantado desde la Fase 4 porque los datasources de la Fase 3 ya lo
/// necesitan.
library;

/// Convierte a `int` un id que puede llegar como `int`, `String` o `num`.
///
/// Lanza [FormatException] con el valor original si no se puede: es preferible
/// a un `null` silencioso que se propaga hasta la base de datos. En la capa de
/// red este throw lo captura `ApiClient` y se convierte en `ParseException`.
int parseId(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();

  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    throw FormatException('Se esperaba un id y llegó: $value');
  }

  final parsed = int.tryParse(text);
  if (parsed == null) {
    throw FormatException('Id no numérico: $value');
  }
  return parsed;
}

/// Igual que [parseId] pero devuelve `null` en vez de lanzar.
int? tryParseId(Object? value) {
  try {
    return parseId(value);
  } on FormatException {
    return null;
  }
}
