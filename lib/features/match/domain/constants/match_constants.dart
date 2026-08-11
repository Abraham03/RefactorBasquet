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

// `MatchStatus` vivía aquí y se mudó a `core/constants/match_status.dart`:
// `MatchesDao` lo escribe, y `core/` no puede importar `features/` (regla 2).
// Es el vocabulario de una columna, no una regla del negocio.

/// Estado de inasistencia (forfeit) de un partido.
abstract final class ForfeitStatus {
  static const String none = 'NONE';
  static const String teamA = 'TEAM_A';
  static const String teamB = 'TEAM_B';
  static const String both = 'BOTH';

  /// ¿Afecta la inasistencia [status] al equipo [side] (`TeamSide.home/away`)?
  ///
  /// **Acepta dos vocabularios a propósito**, porque el código los usa los
  /// dos y no es un descuido:
  ///   - `MatchState.forfeitStatus` guarda `'TEAM_A'`/`'TEAM_B'`/`'BOTH'`.
  ///   - `playersPendingAttendanceByTeam(forfeitOverride:)` recibe el lado
  ///     pelado `'A'`/`'B'`, que es lo que la pantalla de control tiene a
  ///     mano al declarar la inasistencia.
  ///
  /// Antes cada consumidor escribía su propia cadena de `||`, y el generador
  /// del acta solo entendía la forma larga: un `forfeitOverride: 'A'` no le
  /// habría vaciado el roster.
  static bool affects(String status, String side) {
    if (status == both) return true;
    return side == TeamSide.home
        ? status == teamA || status == TeamSide.home
        : status == teamB || status == TeamSide.away;
  }
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
  }) => 'SUB_${side}_OUT_${outId}_IN_$inId';

  static String timeoutFor(String side) => 'TIMEOUT_$side';

  /// Tiempo fuera que el equipo **pierde** al llegar a los dos últimos
  /// minutos sin haber gastado ninguno de la segunda mitad.
  ///
  /// Es un tipo aparte, y no un `TIMEOUT_` normal, porque no es una acción
  /// del anotador: no se puede deshacer y en el acta se marca con una `X` en
  /// lugar del minuto.
  ///
  /// **Se persiste como cualquier otro evento**, en la base local y en la
  /// nube. Antes solo vivía en memoria y había que recalcularlo al
  /// reconstruir el partido —tres intentos costó acertar el cálculo—. Al
  /// guardarlo con su reloj se reproduce en orden cronológico y la marca cae
  /// en su sitio sin ninguna lógica que la coloque.
  static String autoTimeoutFor(String side) => 'TIMEOUT_AUTO_$side';

  /// ¿Es la quema automática, y no un tiempo fuera pedido?
  static bool isAutoTimeout(String type) => type.startsWith('TIMEOUT_AUTO_');

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

  /// ¿Es una falta imputada a un JUGADOR concreto?
  ///
  /// Regla histórica del proyecto: los códigos de falta son cortos
  /// (P, P1, T1, U, D...) de 2 caracteres o menos, o contienen 'FOUL'.
  ///
  /// **Corregido en la Fase 9.** Esa regla de «2 caracteres o menos» hacía
  /// que `isPlayerFoul('C')` e `isPlayerFoul('B')` —técnica al entrenador y
  /// a la banca, en su forma en vivo— devolvieran `true` a la vez que
  /// `isTeamFoul`. No era teórico: `undoLastFoul()` cogía esa falta y hacía
  /// `playerStats[lastFoul.playerId]!` con `playerId == "Entrenador"`, que no
  /// es una clave de `playerStats`. Registrar una técnica al entrenador y
  /// pulsar «deshacer última falta» reventaba la pantalla en pleno partido.
  ///
  /// Quien quiera el total del período (personales **y** técnicas de
  /// banquillo, que en FIBA suman igual) tiene [countsTowardTeamFouls].
  static bool isPlayerFoul(String type) {
    if (isSub(type) || isTimeout(type) || isPossession(type)) return false;
    if (isTeamFoul(type)) return false;
    return type.contains('FOUL') || type.length <= 2;
  }

  /// ¿Suma al contador de faltas de equipo del período?
  ///
  /// Las personales de los jugadores y las técnicas de banquillo cuentan
  /// igual. Existe porque [isPlayerFoul] ya no las mezcla, y el contador del
  /// marcador sí las necesita juntas.
  static bool countsTowardTeamFouls(String type) =>
      isPlayerFoul(type) || isTeamFoul(type);

  /// ¿Es falta del equipo (coach 'C' / banca 'B'), en vivo o con sufijo?
  static bool isTeamFoul(String type) =>
      type == coach ||
      type == bench ||
      type.startsWith('C_') ||
      type.startsWith('B_');

  /// Código de una falta de equipo, sin el sufijo de lado: `'C_A'` → `'C'`.
  ///
  /// Devuelve `null` si no es falta de equipo.
  ///
  /// Existe porque el MISMO evento tiene dos formas: en vivo es `'C'` y al
  /// volver de la base es `'C_A'`. Los consumidores comparaban contra una de
  /// las dos y fallaban con la otra —el acta de un partido reabierto salía
  /// sin las faltas del entrenador ni las de banca—, así que ahora se
  /// normaliza al restaurar y esta es la función que lo hace.
  static String? teamFoulCode(String type) {
    if (type == coach || type.startsWith('C_')) return coach;
    if (type == bench || type.startsWith('B_')) return bench;
    return null;
  }

  /// Lado al que pertenece una falta de equipo persistida: `'C_A'` → `'A'`.
  ///
  /// Devuelve `null` para la forma en vivo (`'C'`), que no lleva lado: ahí el
  /// equipo va en `ScoreEvent.teamId`, no en el tipo.
  static String? teamFoulSide(String type) {
    if (!isTeamFoul(type) || type.length < 3) return null;
    final side = type.substring(2);
    return side == TeamSide.home || side == TeamSide.away ? side : null;
  }
}
