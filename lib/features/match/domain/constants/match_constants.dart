/// Constantes y predicados del dominio de partido.
///
/// Centraliza los strings de tipo de evento y estado que antes vivían
/// como literales repartidos por controllers, generador de PDF y UI.
/// Tener una sola fuente de verdad evita bugs donde un filtro se actualiza
/// y otro queda desfasado (p.ej. 'C' vs 'C_A' en el restore).
library;

/// Lado del equipo dentro de un partido.
abstract final class TeamSide {
  static const String home = 'A';
  static const String away = 'B';
}

/// Estado de un partido (tabla matches / fixtures).
abstract final class MatchStatus {
  static const String scheduled = 'SCHEDULED';
  static const String inProgress = 'IN_PROGRESS';
  static const String finished = 'FINISHED';
  static const String deleted = 'DELETED';
}

/// Estado de inasistencia (forfeit) de un partido.
abstract final class ForfeitStatus {
  static const String none = 'NONE';
  static const String teamA = 'TEAM_A';
  static const String teamB = 'TEAM_B';
  static const String both = 'BOTH';
}

/// Tipos de evento que se guardan en gameEvents.type y en scoreLog.
///
/// Algunos tipos son "compuestos" (llevan datos embebidos en el string):
/// - SUB:  'SUB_<side>_OUT_<outId>_IN_<inId>'
/// - TIMEOUT: 'TIMEOUT_<side>'
/// - POSS: 'POSS_<side>' o 'POSS_NONE'
/// - Falta de equipo: 'C_<side>' / 'B_<side>' (en DB) o 'C' / 'B' (en vivo).
abstract final class EventType {
  // Puntos
  static const String point1 = 'POINT_1';
  static const String point2 = 'POINT_2';
  static const String point3 = 'POINT_3';

  // Falta genérica (cuando no se especifica código)
  static const String foul = 'FOUL';

  // Falta de banco/coach (forma "en vivo", sin sufijo de lado)
  static const String coach = 'C';
  static const String bench = 'B';

  // Cambio
  static const String sub = 'SUB';

  // Posesión (sentinela cuando no hay flecha)
  static const String possNone = 'POSS_NONE';

  // --- Constructores de tipos compuestos ---

  static String pointFor(int points) => 'POINT_$points';

  static String subEvent({
    required String side,
    required String outId,
    required String inId,
  }) =>
      'SUB_${side}_OUT_${outId}_IN_$inId';

  static String timeoutFor(String side) => 'TIMEOUT_$side';

  static String possessionFor(String side) => 'POSS_$side';

  /// Falta de equipo persistida en DB: 'C_A', 'B_B', etc.
  static String teamFoul(String code, String side) => '${code}_$side';

  // --- Predicados (una sola fuente de verdad) ---

  static bool isSub(String type) => type == sub || type.startsWith('SUB_');

  static bool isTimeout(String type) => type.contains('TIMEOUT');

  static bool isPossession(String type) => type.startsWith('POSS_');

  static int pointsOf(String type) {
    switch (type) {
      case point1:
        return 1;
      case point2:
        return 2;
      case point3:
        return 3;
      default:
        return 0;
    }
  }

  /// ¿Es una falta de jugador? (excluye puntos, cambios, tiempos muertos,
  /// posesión y faltas de coach/banca con sufijo).
  ///
  /// Regla histórica del proyecto: los códigos de falta son cortos
  /// (P, P1, T1, U, D...) de 2 caracteres o menos, o contienen 'FOUL'.
  static bool isPlayerFoul(String type) {
    if (isSub(type) || isTimeout(type) || isPossession(type)) return false;
    return type.contains('FOUL') || type.length <= 2;
  }

  /// ¿Es falta del equipo (coach 'C' / banca 'B'), en vivo o con sufijo?
  static bool isTeamFoul(String type) =>
      type == coach ||
      type == bench ||
      type.startsWith('C_') ||
      type.startsWith('B_');
}