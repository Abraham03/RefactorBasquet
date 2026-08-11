import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:myapp/core/database/app_database.dart'; // Importa tu DB
import 'package:myapp/core/database/tables/app_tables.dart';
import 'package:myapp/core/database/daos/roster_with_name.dart';
import 'package:myapp/core/constants/match_status.dart';

part 'matches_dao.g.dart'; // Drift generará esto

@DriftAccessor(tables: [Matches, MatchRosters, GameEvents])
class MatchesDao extends DatabaseAccessor<AppDatabase> with _$MatchesDaoMixin {
  MatchesDao(super.db);

  // Crear un partido
  Future<void> createMatch(MatchesCompanion match) async {
    try {
      await into(matches).insert(match);
    } catch (e) {
      // Aquí manejas la excepción específica de BD y la lanzas como una de tu dominio
      throw Exception('Error al crear partido: $e');
    }
  }

  // --- ACTUALIZACIÓN (NUEVO) ---
  // Guardar el estado actual del partido (Persistencia Real)
  Future<void> updateMatchStatus(
    String matchId,
    int scoreA,
    int scoreB,
    String clockTime,
    String status, {
    String? forfeitStatus,
    String? observaciones,
    int? currentPeriod,
  }) async {
    await (update(matches)..where((t) => t.id.equals(matchId))).write(
      MatchesCompanion(
        scoreA: Value(scoreA),
        scoreB: Value(scoreB),
        status: Value(status),
        clockTime: Value(clockTime),
        currentPeriod: currentPeriod == null
            ? const Value.absent()
            : Value(currentPeriod),
        forfeitStatus: forfeitStatus == null
            ? const Value.absent()
            : Value(forfeitStatus),
        observaciones: observaciones == null
            ? const Value.absent()
            : Value(observaciones),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
      ),
    );
  }

  /// Guarda el desenlace corregido de un partido YA finalizado.
  ///
  /// Existe porque [updateMatchStatus] no sirve aquí: escribe `IN_PROGRESS` y
  /// `isSynced: false`, que es lo correcto mientras se juega y lo contrario de
  /// lo que hace falta al corregir un acta cerrada. El controller se protegía
  /// de eso saltándose la escritura entera cuando el partido estaba
  /// finalizado, así que el cambio de desenlace **no llegaba nunca a la base
  /// local**: la nube quedaba bien y el teléfono seguía mostrando el marcador
  /// viejo hasta la siguiente descarga del catálogo.
  ///
  /// No toca `status` ni `isSynced`: el partido sigue cerrado, y sigue
  /// sincronizado porque el llamador solo invoca esto cuando el servidor ya
  /// aceptó el cambio.
  Future<void> applyOutcomeChange(
    String matchId, {
    required int scoreA,
    required int scoreB,
    required String forfeitStatus,
    required String observaciones,
  }) async {
    await (update(matches)..where((t) => t.id.equals(matchId))).write(
      MatchesCompanion(
        scoreA: Value(scoreA),
        scoreB: Value(scoreB),
        forfeitStatus: Value(forfeitStatus),
        observaciones: Value(observaciones),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Devuelve la fila del partido por su ID, o null si no existe.
  Future<BasketballMatch?> getMatchById(String matchId) {
    return (select(
      matches,
    )..where((t) => t.id.equals(matchId))).getSingleOrNull();
  }

  // Método para guardar metadatos del partido (Árbitros, IDs, etc.)
  Future<void> updateMatchMetadata(
    String matchId,
    String? fixtureId,
    int teamAId,
    int teamBId,
    String mainRef,
    String auxRef,
    String scorek, {
    bool markInProgress = true, // ← false al reabrir un partido FINALIZADO
  }) async {
    await (update(matches)..where((t) => t.id.equals(matchId))).write(
      MatchesCompanion(
        teamAId: Value(teamAId),
        teamBId: Value(teamBId),
        mainReferee: Value(mainRef),
        auxReferee: Value(auxRef),
        scorekeeper: Value(scorek),
        // Solo se marca pendiente de subir al INICIAR un partido. Al reabrir
        // uno finalizado —para corregir su desenlace— se deja como estaba.
        //
        // Escribir `false` aquí sin condición era un bug de verdad: reabrir
        // un acta ya subida la devolvía a la cola de pendientes, y la
        // siguiente sincronización la volvía a mandar entera, PDF incluido,
        // duplicándola en el servidor. El bloque de abajo ya cuidaba de no
        // revertir el estado del calendario; esta línea deshacía la mitad de
        // ese cuidado.
        isSynced: markInProgress ? const Value(false) : const Value.absent(),
      ),
    );

    if (fixtureId != null) {
      // Vinculamos el partido con el calendario. Solo marcamos IN_PROGRESS al
      // INICIAR un partido; al reabrir uno finalizado (cambio de desenlace)
      // NO tocamos el status para no revertir el FINISHED del calendario.
      await (db.update(
        db.fixtures,
      )..where((f) => f.id.equals(fixtureId))).write(
        markInProgress
            ? FixturesCompanion(
                matchId: Value(matchId),
                status: const Value(MatchStatus.inProgress),
              )
            : FixturesCompanion(matchId: Value(matchId)),
      );
    }
  }

  // Agrega también el campo para la firma
  Future<int> saveSignature(String matchId, String signatureBase64) async {
    // Convertimos a String explícitamente por seguridad
    final idStr = matchId.toString();
    final rowAffected =
        await (update(matches)..where((t) => t.id.equals(idStr))).write(
          MatchesCompanion(
            signatureData: Value(signatureBase64),
            isSynced: const Value(false),
          ),
        );

    return rowAffected;
  }

  // Marcar un partido como SINCRONIZADO
  Future<void> markAsSynced(String matchId) async {
    await (update(matches)..where((t) => t.id.equals(matchId))).write(
      const MatchesCompanion(isSynced: Value(true)),
    );
  }

  // Registra cada punto o falta como un evento individual
  Future<void> insertEvent(GameEventsCompanion event) async {
    await into(gameEvents).insert(event);
  }

  /// Borra eventos concretos por id.
  ///
  /// Lo usa el deshacer general: el controller lleva la lista de los eventos
  /// que **él** ha escrito, así que borrar por id no puede tocar los de una
  /// sesión anterior de un partido reabierto.
  Future<int> deleteEventsByIds(List<String> ids) async {
    if (ids.isEmpty) return 0;
    return (delete(gameEvents)..where((e) => e.id.isIn(ids))).go();
  }

  /// Borra el evento persistido **más reciente** que encaje.
  ///
  /// Lo usan los deshacer concretos (punto, falta, cambio), que sí pueden
  /// caer sobre un evento de una sesión anterior —un partido reanudado trae
  /// los suyos de la base— y por eso no sirve la lista de ids.
  ///
  /// Se ordena por `createdAt` y, a igualdad, por `id`: dos eventos del mismo
  /// segundo son frecuentes cuando el anotador va rápido.
  Future<int> deleteLastEventOfType(
    String matchId, {
    required String type,
    required int period,
    String? playerId,
  }) async {
    final query = select(gameEvents)
      ..where(
        (e) =>
            e.matchId.equals(matchId) &
            e.type.equals(type) &
            e.period.equals(period),
      )
      ..orderBy([
        (e) => OrderingTerm.desc(e.createdAt),
        (e) => OrderingTerm.desc(e.id),
      ])
      ..limit(1);

    if (playerId != null) {
      query.where((e) => e.playerId.equals(playerId));
    }

    final row = await query.getSingleOrNull();
    if (row == null) return 0;
    return (delete(gameEvents)..where((e) => e.id.equals(row.id))).go();
  }

  // Ejemplo de Transacción (Atomicidad)
  // Útil cuando registras un equipo completo: o se guardan todos o ninguno.
  Future<void> addRosterToMatch(
    String matchId,
    List<MatchRostersCompanion> roster,
  ) async {
    return transaction(() async {
      for (var player in roster) {
        await into(matchRosters).insert(player);
      }
    });
  }

  /// Marca la asistencia de un jugador en un partido concreto.
  Future<void> setPlayerAttendance(
    String matchId,
    String playerId,
    bool attended,
  ) {
    return (update(matchRosters)..where(
          (r) => r.matchId.equals(matchId) & r.playerId.equals(playerId),
        ))
        .write(MatchRostersCompanion(attended: Value(attended)));
  }

  /// Marca en lote la asistencia de varios jugadores del partido.
  Future<void> setAttendanceBatch(
    String matchId,
    Map<String, bool> byPlayerId,
  ) async {
    await batch((b) {
      byPlayerId.forEach((playerId, attended) {
        b.update(
          matchRosters,
          MatchRostersCompanion(
            attended: Value(attended),
            isSynced: const Value(false), // ← marca pendiente de subir
          ),
          where: (r) => r.matchId.equals(matchId) & r.playerId.equals(playerId),
        );
      });
    });
  }

  /// Devuelve el roster completo de un partido.
  Future<List<RosterEntry>> getRostersForMatch(String matchId) {
    return (select(
      matchRosters,
    )..where((r) => r.matchId.equals(matchId))).get();
  }

  /// Guarda localmente un jugador creado a mitad de un partido.
  /// Soporta modo Online (ID real, isSynced: true) y Offline (ID negativo, isSynced: false).
  Future<void> saveMidGamePlayerLocally({
    required String matchId,
    required int playerId, // ID real o ID negativo temporal
    required int teamId,
    required String name,
    required int number,
    required String teamSide,
    bool isSynced =
        true, // <--- NUEVO: Por defecto true, pero en offline pasaremos false
  }) async {
    try {
      await transaction(() async {
        // 1. Insertar en el catálogo global de Jugadores (Players)
        await db
            .into(db.players)
            .insert(
              PlayersCompanion.insert(
                id: Value(playerId.toString()),
                teamId: teamId,
                name: name,
                defaultNumber: Value(number),
                isSynced: Value(isSynced), // <--- Dependerá de si hubo red o no
              ),
              mode: InsertMode.insertOrReplace,
            );

        // 2. Vincular el jugador al partido actual (MatchRosters)
        await into(matchRosters).insert(
          MatchRostersCompanion.insert(
            matchId: matchId,
            playerId: playerId.toString(),
            teamSide: teamSide,
            jerseyNumber: number,
            isCaptain: const Value(false),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      });
    } catch (e) {
      throw Exception('Error al persistir el jugador localmente en BD: $e');
    }
  }

  // =========================================================================
  // --- RECONCILIACIÓN OFFLINE-FIRST ---
  // =========================================================================

  /// Intercambia el ID temporal (negativo) por el ID real de la nube.
  /// Utiliza la estrategia Insertar -> Revincular -> Eliminar para evitar
  /// violaciones de llaves foráneas (Foreign Key Constraints) en SQLite.
  Future<void> replaceTempPlayerId(String oldTempId, String newRealId) async {
    try {
      await transaction(() async {
        // 1. Obtener los datos completos del jugador temporal
        final oldPlayer = await (db.select(
          db.players,
        )..where((p) => p.id.equals(oldTempId))).getSingleOrNull();

        if (oldPlayer != null) {
          // 2. Insertar el "clon" del jugador, pero usando el ID real y marcado como sincronizado
          await db
              .into(db.players)
              .insert(
                PlayersCompanion.insert(
                  id: Value(newRealId),
                  teamId: oldPlayer.teamId,
                  name: oldPlayer.name,
                  defaultNumber: Value(oldPlayer.defaultNumber),
                  active: Value(oldPlayer.active),
                  isSynced: const Value(
                    true,
                  ), // El nuevo ID siempre viene de la nube, ya está sincronizado
                ),
                mode: InsertMode.insertOrReplace,
              );
        }

        // 3. Revincular (Actualizar) todas las tablas hijas para que apunten al ID real
        await (update(matchRosters)..where((t) => t.playerId.equals(oldTempId)))
            .write(MatchRostersCompanion(playerId: Value(newRealId)));

        await (update(gameEvents)..where((t) => t.playerId.equals(oldTempId)))
            .write(GameEventsCompanion(playerId: Value(newRealId)));

        // 3b. Revincular los IDs incrustados en el TEXTO del evento de cambio (SUB).
        //     Formato: 'SUB_A_OUT_<id>_IN_<id>'. El ID del SUB no vive en playerId
        //     (que es null), solo en 'type', por lo que el paso 3 no lo alcanzaba.
        final subEvents = await (select(
          gameEvents,
        )..where((e) => e.type.like('%$oldTempId%'))).get();
        for (final ev in subEvents) {
          await (update(gameEvents)..where((e) => e.id.equals(ev.id))).write(
            GameEventsCompanion(
              type: Value(ev.type.replaceAll(oldTempId, newRealId)),
            ),
          );
        }

        // 4. Eliminar el jugador temporal original (ya no tiene hijos dependientes)
        if (oldPlayer != null) {
          await (db.delete(
            db.players,
          )..where((p) => p.id.equals(oldTempId))).go();
        }
      });
    } catch (e) {
      throw Exception('Error reconciliando IDs del jugador: $e');
    }
  }

  // =========================================================================
  // --- SINCRONIZACIÓN MAESTRA OFFLINE-FIRST ---
  // =========================================================================

  /// Se ejecuta ANTES de sincronizar los partidos atrasados.
  /// Busca todos los jugadores con ID negativo y los sube a la nube.
  ///
  /// Recibe la subida como callback en vez del datasource: así este DAO, que
  /// es infraestructura de `core/`, no tiene que importar `features/`
  /// (regla 2 del plan). Antes el parámetro era `dynamic`, que ocultaba el
  /// acoplamiento y desactivaba toda comprobación de tipos.
  /// [uploadPlayer] devuelve el id real, o `null` si la subida falló.
  Future<void> syncOfflinePlayersBeforeMatches(
    Future<int?> Function(int teamId, String name, int number) uploadPlayer,
  ) async {
    // Buscamos jugadores que tengan isSynced en false
    final offlinePlayers = await (select(
      db.players,
    )..where((p) => p.isSynced.equals(false))).get();

    for (var p in offlinePlayers) {
      final int oldId = int.tryParse(p.id) ?? 0;

      // Confirmamos que es un ID temporal generado por nosotros (Negativo)
      if (oldId < 0) {
        try {
          // 1. Subimos a la nube
          final realId = await uploadPlayer(p.teamId, p.name, p.defaultNumber);
          if (realId == null) continue;

          // 2. Usamos el método de Reconciliación para corregir la BD local
          await replaceTempPlayerId(p.id, realId.toString());
        } catch (e) {
          // Ignoramos el error para que el bucle siga intentando con otros jugadores
          // Si este falla, el partido que depende de él también fallará la subida,
          // pero el usuario podrá intentarlo de nuevo más tarde.
          debugPrint("Fallo al sincronizar jugador offline: ${p.name}");
        }
      }
    }
  }

  /// Roster de un partido con el nombre de cada jugador (join con players),
  /// para pantallas de edición que necesitan mostrar nombres.
  Future<List<RosterWithName>> getRosterWithNames(String matchId) async {
    final query = select(matchRosters).join([
      leftOuterJoin(players, players.id.equalsExp(matchRosters.playerId)),
    ])..where(matchRosters.matchId.equals(matchId));

    final rows = await query.get();
    return rows.map((row) {
      final roster = row.readTable(matchRosters);
      final player = row.readTableOrNull(players);
      return RosterWithName(
        playerId: roster.playerId,
        name: player?.name ?? "Jugador ${roster.playerId}",
        jerseyNumber: roster.jerseyNumber,
        teamSide: roster.teamSide,
        attended: roster.attended,
      );
    }).toList();
  }
}
