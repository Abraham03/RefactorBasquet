/// Acorta nombres que no caben en su casilla del acta.
///
/// El acta se dibuja sobre una plantilla de imagen con coordenadas fijas, así
/// que un nombre largo no se recorta: **invade la casilla de al lado**. En un
/// acta de campo se llegó a imprimir `PRUEBA ACTUALIZACIONFecha 11/08/2026`,
/// con el torneo comiéndose el campo de la fecha, y `Marcador: COBRAS 7 - 6
/// CLIPPERS NUEVA GENE` cortado en seco.
///
/// Reducir el tamaño de letra se descartó: en una hoja que se firma y se
/// fotocopia, un nombre en cuerpo 5 no se lee. Se abrevia, que es lo que hace
/// un anotador a mano.
///
/// La medida se inyecta como predicado [fits] a propósito: aquí no se sabe de
/// tipografías ni de puntos: quien llama mide con la fuente real del PDF.
abstract final class NameAbbreviator {
  /// Palabras que se van primero porque no identifican a nadie.
  /// `CLUB DEPORTIVO DE LA MONTAÑA` → `CLUB DEPORTIVO MONTAÑA`.
  static const Set<String> _connectors = {
    'DE',
    'DEL',
    'LA',
    'LAS',
    'EL',
    'LOS',
    'Y',
    'EN',
  };

  /// Devuelve [raw] tal cual si ya cabe; si no, la versión más larga que quepa.
  ///
  /// La escalera va de menos a más agresiva, y para en cuanto algo entra:
  ///  1. Quitar conectores.
  ///  2. Dejar en inicial las palabras finales, una a una, **de atrás hacia
  ///     adelante**: la primera es la que identifica al equipo, y es la última
  ///     que se toca (`CLIPPERS NUEVA GENERACION` → `CLIPPERS NUEVA G.` →
  ///     `CLIPPERS N. G.`).
  ///  3. Recorte con punto, para el caso de una sola palabra kilométrica.
  static String fit(String raw, {required bool Function(String) fits}) {
    final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || fits(name)) return name;

    var words = name.split(' ');

    if (words.length > 1) {
      // El primer término nunca se descarta aunque sea un conector: hay
      // equipos que se llaman «LOS ANGELES».
      final trimmed = [
        words.first,
        ...words.skip(1).where((w) => !_connectors.contains(w.toUpperCase())),
      ];
      if (trimmed.length > 1) words = trimmed;
      if (fits(words.join(' '))) return words.join(' ');
    }

    for (var i = words.length - 1; i >= 1; i--) {
      words[i] = '${words[i].substring(0, 1)}.';
      final candidate = words.join(' ');
      if (fits(candidate)) return candidate;
    }

    return _clip(words.join(' '), fits: fits);
  }

  /// Último recurso: cortar y marcar el corte con un punto.
  static String _clip(String text, {required bool Function(String) fits}) {
    for (var cut = text.length - 1; cut > 0; cut--) {
      final candidate = '${_stripTail(text.substring(0, cut))}.';
      if (fits(candidate)) return candidate;
    }
    // Ni un carácter cabe: el llamador ha dado un ancho inservible. Se
    // devuelve algo antes que nada, para no imprimir una casilla en blanco.
    return text.substring(0, 1);
  }

  /// Quita espacios y puntos del final para no acabar en `CLIPPERS N..`.
  static String _stripTail(String text) {
    var end = text.length;
    while (end > 0 && (text[end - 1] == ' ' || text[end - 1] == '.')) {
      end--;
    }
    return text.substring(0, end);
  }
}
