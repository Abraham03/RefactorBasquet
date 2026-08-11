/// Valores admitidos por la columna `status` de `matches` y `fixtures`.
///
/// **Por qué vive en `core/` y no en `features/match/domain/`,** donde están
/// `TeamSide`, `EventType` y `ForfeitStatus`: `MatchesDao` —que se queda en
/// `core/database/` porque su `.g.dart` está acoplado al de `AppDatabase`—
/// escribe este estado. Dejarlo en la feature obligaba a `core/` a importar
/// `features/`, que es justo lo que prohíbe la regla 2 del plan.
///
/// El criterio: esto no es una regla del negocio, es el **vocabulario de una
/// columna**, y la columna se define en `core/database/tables/app_tables.dart`.
/// Las otras tres agrupaciones no las usa nadie de `core/`, así que se quedan
/// en el dominio de la feature.
library;

abstract final class MatchStatus {
  static const String scheduled = 'SCHEDULED';
  static const String inProgress = 'IN_PROGRESS';
  static const String finished = 'FINISHED';
  static const String deleted = 'DELETED';

  /// Partido cancelado. Solo lo escribe el backend; la app lo filtra al
  /// listar el calendario, nunca lo asigna.
  static const String cancelled = 'CANCELLED';
}
