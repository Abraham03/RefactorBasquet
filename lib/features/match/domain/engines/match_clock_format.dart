/// El reloj tal como se guarda en la base de datos y en cada evento.
///
/// Se formatea al escribir (`_saveToDatabase`, `_logEventToDb`) y se vuelve a
/// leer al reanudar un partido interrumpido. Las dos mitades estaban escritas
/// a mano en sitios distintos, así que nada garantizaba que encajaran: si el
/// formato y el parseo se desincronizan, un partido a medias se reanuda con el
/// reloj equivocado.
abstract final class MatchClockFormat {
  /// Reloj por defecto cuando lo guardado no se puede interpretar.
  ///
  /// Diez minutos es la duración estándar de un período: ante la duda es
  /// preferible dar tiempo de más y que el anotador lo ajuste, a arrancar en
  /// cero y dar el período por terminado.
  static const Duration fallback = Duration(minutes: 10);

  /// `Duration` → `"m:ss"`. Los minutos NO se rellenan con cero a la
  /// izquierda; los segundos sí.
  static String format(Duration timeLeft) {
    final seconds = timeLeft.inSeconds.clamp(0, 1 << 30);
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  /// `"m:ss"` → `Duration`. Devuelve [fallback] si el texto no sirve.
  ///
  /// Es tolerante a propósito: lo que hay guardado puede venir de una versión
  /// anterior o haberse escrito con relleno (`"04:59"`).
  static Duration parse(String? raw) {
    if (raw == null || !raw.contains(':')) return fallback;

    final parts = raw.split(':');
    final minutes = int.tryParse(parts[0].trim());
    final seconds = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;

    // Si los minutos no se entienden se usa el valor por defecto, pero unos
    // segundos ilegibles solo valen 0: el minuto ya da la información útil.
    if (minutes == null) return fallback;
    return Duration(minutes: minutes, seconds: seconds ?? 0);
  }
}
