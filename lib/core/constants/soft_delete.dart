/// Borrado lógico de sedes y oficiales.
///
/// No hay columna `deleted`: se marca **prefijando el nombre**. La fila se
/// queda con `isSynced: false` para que la subida siguiente se la lleve al
/// backend, y las pantallas filtran por el prefijo.
///
/// Es un dato que ya vive en las bases instaladas y viaja al backend, así que
/// la cadena no puede cambiar (I2/I3 del plan). Se centraliza porque estaba
/// repetida en 8 sitios: bastaba una errata en uno de los filtros para que
/// una sede borrada reapareciera en el desplegable de crear partido.
abstract final class SoftDelete {
  static const String prefix = '[DEL]-';

  /// ¿Está marcada como borrada?
  static bool isDeleted(String name) => name.startsWith(prefix);

  /// Nombre ya marcado. Idempotente: marcar dos veces no encadena prefijos.
  static String mark(String name) => isDeleted(name) ? name : '$prefix$name';
}
