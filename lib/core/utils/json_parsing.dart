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

/// Interpreta como booleano lo que el backend PHP manda como `1`, `"1"`,
/// `true` o `"true"`.
///
/// Estaba como `_toBool` privado dentro de `home_menu_screen`, justo donde no
/// se podía reutilizar ni probar.
bool parseBool(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  final text = value.toString().toLowerCase().trim();
  return text == '1' || text == 'true';
}

/// Entero tolerante: devuelve `null` si el valor no es numérico.
/// Para campos opcionales como un marcador aún no jugado.
int? parseIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}
