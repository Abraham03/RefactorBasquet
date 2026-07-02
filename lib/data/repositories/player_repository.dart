import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/database/app_database.dart';
import '../../core/service/api_service.dart';

/// Resultado de guardar un jugador: si se sincronizó a la nube y con qué ID
/// quedó (real si hubo red, temporal negativo si fue offline).
class SavePlayerResult {
  final bool synced;
  final String playerId;
  const SavePlayerResult({required this.synced, required this.playerId});
}

/// Acceso a datos de jugadores. Encapsula el CRUD y su reconciliación
/// online/offline, para que la UI no toque ApiService ni la BD directamente.
///
/// El repositorio NO decide UI (no muestra diálogos ni mensajes): devuelve
/// datos/resultados y la pantalla presenta.
class PlayerRepository {
  final AppDatabase _db;
  final ApiService _api;

  PlayerRepository(this._db, this._api);

  /// Busca en un equipo un jugador que ya use [number], excluyendo opcionalmente
  /// a [excludePlayerId] (el que estamos editando). Devuelve null si está libre.
  Future<Player?> findPlayerByNumber({
    required int teamId,
    required int number,
    String? excludePlayerId,
  }) async {
    final query = _db.select(_db.players)
      ..where((p) => p.teamId.equals(teamId) & p.defaultNumber.equals(number));
    final matches = await query.get();
    for (final p in matches) {
      if (excludePlayerId != null && p.id == excludePlayerId) continue;
      return p;
    }
    return null;
  }

  /// Cambia el dorsal de un jugador que ya existe (el "duplicado" al que le
  /// quitamos el número). [freeUpFirstId] mueve temporalmente a ese jugador
  /// al #9999 en la nube para evitar el deadlock de dorsal único en el backend.
  Future<void> reassignNumber({
    required Player duplicatePlayer,
    required int newNumber,
    required int teamId,
    required bool isTeamLocal,
    String? freeUpFirstId,
    String? freeUpFirstName,
  }) async {
    bool synced = false;
    final isRealDupId = (int.tryParse(duplicatePlayer.id) ?? 0) > 0;

    if (isRealDupId && !isTeamLocal) {
      try {
        if (freeUpFirstId != null && freeUpFirstName != null) {
          await _api.updatePlayer(freeUpFirstId, teamId, freeUpFirstName, 9999);
        }
        synced = await _api.updatePlayer(
            duplicatePlayer.id, teamId, duplicatePlayer.name, newNumber);
      } catch (_) {}
    }

    await (_db.update(_db.players)..where((p) => p.id.equals(duplicatePlayer.id)))
        .write(PlayersCompanion(
      defaultNumber: Value(newNumber),
      isSynced: Value(synced),
    ));
  }

  /// Actualiza un jugador existente (online si hay red, si no queda pendiente).
  Future<SavePlayerResult> updatePlayer({
    required String playerId,
    required int teamId,
    required String name,
    required int number,
    required bool isTeamLocal,
  }) async {
    final isRealId = (int.tryParse(playerId) ?? 0) > 0;
    bool synced = false;

    if (isRealId && !isTeamLocal) {
      synced = await _api.updatePlayer(playerId, teamId, name, number);
    }

    await (_db.update(_db.players)..where((t) => t.id.equals(playerId))).write(
      PlayersCompanion(
        name: Value(name),
        defaultNumber: Value(number),
        isSynced: Value(synced),
      ),
    );

    return SavePlayerResult(synced: synced, playerId: playerId);
  }

  /// Crea un jugador nuevo. Intenta online; si falla o el equipo es local,
  /// lo guarda offline con ID temporal negativo. Lanza sólo si es un error
  /// inesperado en creación online que la UI deba mostrar.
  Future<SavePlayerResult> createPlayer({
    required int teamId,
    required String name,
    required int number,
    required bool isTeamLocal,
  }) async {
    // Equipo local → forzamos cascada offline directamente.
    if (isTeamLocal) {
      return _createOffline(teamId: teamId, name: name, number: number);
    }

    try {
      final newId = await _api.addPlayer(teamId, name, number);
      await _db.into(_db.players).insert(
            PlayersCompanion.insert(
              id: Value(newId.toString()),
              teamId: teamId,
              name: name,
              defaultNumber: Value(number),
              active: const Value(true),
              isSynced: const Value(true),
            ),
            mode: InsertMode.insertOrReplace,
          );
      return SavePlayerResult(synced: true, playerId: newId.toString());
    } catch (e) {
      debugPrint("Creación online falló, guardando offline: $e");
      return _createOffline(teamId: teamId, name: name, number: number);
    }
  }

  Future<SavePlayerResult> _createOffline({
    required int teamId,
    required String name,
    required int number,
  }) async {
    final tempId = (-DateTime.now().millisecondsSinceEpoch).toString();
    await _db.into(_db.players).insert(
          PlayersCompanion.insert(
            id: Value(tempId),
            teamId: teamId,
            name: name,
            defaultNumber: Value(number),
            active: const Value(true),
            isSynced: const Value(false),
          ),
        );
    return SavePlayerResult(synced: false, playerId: tempId);
  }

  /// Devuelve el dorsal libre más bajo del equipo (empezando en 0),
  /// ignorando opcionalmente a [excludePlayerId]. Se usa para reasignar
  /// a un jugador cuyo número le fue quitado, sin chocar con otro existente.
  Future<int> findLowestFreeNumber({
    required int teamId,
    String? excludePlayerId,
  }) async {
    final players = await (_db.select(_db.players)
          ..where((p) => p.teamId.equals(teamId)))
        .get();

    final taken = <int>{};
    for (final p in players) {
      if (excludePlayerId != null && p.id == excludePlayerId) continue;
      taken.add(p.defaultNumber);
    }

    int candidate = 0;
    while (taken.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }

  /// Borra un jugador localmente.
  Future<void> deletePlayer(String playerId) async {
    await (_db.delete(_db.players)..where((t) => t.id.equals(playerId))).go();
  }
}