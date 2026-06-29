// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;

import '../core/models/catalog_models.dart';
import '../core/database/app_database.dart' as db_app;
import '../core/di/dependency_injection.dart' as di;
import '../ui/widgets/app_background.dart';
import '../ui/widgets/app_feedback.dart';


class TeamDetailScreen extends ConsumerWidget {
  final Team team;
  const TeamDetailScreen({super.key, required this.team});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamIdInt = int.tryParse(team.id.toString()) ?? 0;
    final playersAsync = ref.watch(teamPlayersStreamProvider(teamIdInt));
    final isTeamLocal = teamIdInt < 0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          children: [
            Text(
              team.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Text(
              "Plantilla de Jugadores",
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (isTeamLocal)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Tooltip(
                message: "Equipo local (no sincronizado)",
                child: Icon(Icons.cloud_off, color: Colors.orangeAccent),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showPlayerDialog(context, ref, teamIdInt, isTeamLocal),
        label: const Text(
          "Nuevo Jugador",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.person_add),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
      ),

      body: AppBackground(
        opacity: 0.5,
        child: SafeArea(
          child: playersAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            ),
            error: (err, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.redAccent,
                  ),
                  Text(
                    "Error: $err",
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            data: (players) {
              if (players.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.sports_handball,
                          size: 60,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "No hay jugadores registrados.",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Agrega jugadores usando el botón inferior.",
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
                    ],
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 400,
                            mainAxisExtent: 90,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                      itemCount: players.length,
                      itemBuilder: (context, index) {
                        final player = players[index];
                        return _buildDismissiblePlayer(
                          context,
                          ref,
                          player,
                          teamIdInt,
                          isTeamLocal,
                        );
                      },
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final player = players[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: _buildDismissiblePlayer(
                          context,
                          ref,
                          player,
                          teamIdInt,
                          isTeamLocal,
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDismissiblePlayer(
    BuildContext context,
    WidgetRef ref,
    db_app.Player player,
    int teamIdInt,
    bool isTeamLocal,
  ) {
    return Dismissible(
      key: Key(player.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E2432),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              "¿Eliminar jugador?",
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              "¿Estás seguro de eliminar a ${player.name}?",
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("No", style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Sí, eliminar",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        final db = ref.read(di.databaseProvider);
        await (db.delete(
          db.players,
        )..where((t) => t.id.equals(player.id))).go();
      },
      child: GestureDetector(
        onTap: () => _showPlayerDialog(
          context,
          ref,
          teamIdInt,
          isTeamLocal,
          playerToEdit: player,
        ),
        child: _PlayerCard(player: player),
      ),
    );
  }

  void _showPlayerDialog(
    BuildContext context,
    WidgetRef ref,
    int teamIdInt,
    bool isTeamLocal, {
    db_app.Player? playerToEdit,
  }) {
    final isEditing = playerToEdit != null;
    final nameCtrl = TextEditingController(text: playerToEdit?.name ?? "");
    final numberCtrl = TextEditingController(
      text: playerToEdit?.defaultNumber.toString() ?? "",
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2432),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isEditing ? Icons.edit : Icons.person_add,
              color: Colors.orangeAccent,
            ),
            const SizedBox(width: 10),
            Text(
              isEditing ? "Editar Jugador" : "Registrar Jugador",
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: "Nombre Completo",
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.orangeAccent)),
                prefixIcon: const Icon(Icons.person, color: Colors.white54),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: numberCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Número (#)",
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.orangeAccent)),
                prefixIcon: const Icon(Icons.format_list_numbered, color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) {
                context.showWarning("El nombre es obligatorio.");
                return;
              }
              
              final db = ref.read(di.databaseProvider);
              final api = ref.read(di.apiServiceProvider);
              final playerNum = int.tryParse(numberCtrl.text) ?? 0;
              final currentPlayers = ref.read(teamPlayersStreamProvider(teamIdInt)).value ?? [];
              
              // =================================================================
              // LÓGICA DE SWAP (INTERCAMBIO)
              // =================================================================
              final duplicates = currentPlayers.where((p) => p.defaultNumber == playerNum && p.id != playerToEdit?.id);
              
              if (duplicates.isNotEmpty) {
                final duplicatePlayer = duplicates.first;
                final numberForDuplicate = isEditing ? playerToEdit.defaultNumber : 0; // Si es nuevo, le damos 0 al otro
                
                final confirmSwap = await showDialog<bool>(
                  context: context,
                  builder: (swapCtx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E2432),
                    title: const Text("🔄 Número Ocupado", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    content: Text(
                      "El jugador ${duplicatePlayer.name} ya usa el número $playerNum.\n\n"
                      "¿Deseas quitárselo${isEditing ? ' e intercambiar sus números' : ' y asignarle el 0'}?",
                      style: const TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(swapCtx, false), child: const Text("Cancelar")),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
                        onPressed: () => Navigator.pop(swapCtx, true),
                        child: const Text("Sí, Intercambiar", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );

                if (confirmSwap != true) return; // Si no confirma, no hacemos nada

                // 1. Ejecutar el cambio en el jugador duplicado primero
                bool syncSuccessDup = false;
                final isRealDupId = (int.tryParse(duplicatePlayer.id) ?? 0) > 0;
                
                if (isRealDupId && !isTeamLocal) {
                  try {
                    // --- TRUCO ANTI-DEADLOCK ONLINE ---
                    // Movemos al jugador original al #9999 para que PHP no bloquee al duplicado
                    if (isEditing) {
                        await api.updatePlayer(playerToEdit.id, teamIdInt, playerToEdit.name, 9999);
                    }
                    syncSuccessDup = await api.updatePlayer(duplicatePlayer.id, teamIdInt, duplicatePlayer.name, numberForDuplicate);
                  } catch (_) {}
                }
                
                await (db.update(db.players)..where((p) => p.id.equals(duplicatePlayer.id.toString()))).write(
                  db_app.PlayersCompanion(
                    defaultNumber: drift.Value(numberForDuplicate),
                    isSynced: drift.Value(syncSuccessDup),
                  )
                );
              }

              // =================================================================
              // GUARDADO DEL JUGADOR PRINCIPAL
              // =================================================================
              try {
                if (isEditing) {
                  final isRealId = (int.tryParse(playerToEdit.id) ?? 0) > 0;
                  bool syncSuccess = false;

                  if (isRealId && !isTeamLocal) {
                    syncSuccess = await api.updatePlayer(playerToEdit.id, teamIdInt, nameCtrl.text, playerNum);
                  }

                  await (db.update(db.players)..where((t) => t.id.equals(playerToEdit.id))).write(
                    db_app.PlayersCompanion(
                      name: drift.Value(nameCtrl.text),
                      defaultNumber: drift.Value(playerNum),
                      isSynced: drift.Value(syncSuccess),
                    ),
                  );
                  
                  if (context.mounted) {
                    if (syncSuccess) {
                      context.showSuccess("Jugador actualizado en la nube");
                    }else {
                      context.showWarning("Jugador editado localmente (Pendiente de subir)");
                    }
                  }
                } else {
                  if (isTeamLocal) {
                    throw Exception("Equipo padre es local. Forzando cascada offline.");
                  }

                  final newId = await api.addPlayer(teamIdInt, nameCtrl.text, playerNum);
                  await db.into(db.players).insert(
                    db_app.PlayersCompanion.insert(
                      id: drift.Value(newId.toString()),
                      teamId: teamIdInt,
                      name: nameCtrl.text,
                      defaultNumber: drift.Value(playerNum),
                      active: const drift.Value(true),
                      isSynced: const drift.Value(true),
                    ),
                    mode: drift.InsertMode.insertOrReplace,
                  );
                  
                  if (context.mounted) {context.showSuccess("Jugador agregado");}
                }
                
                if (context.mounted) Navigator.pop(ctx);
                
              } catch (e) {
                if (!isEditing) {
                  // Creación Offline
                  final tempId = (-DateTime.now().millisecondsSinceEpoch).toString();
                  await db.into(db.players).insert(
                    db_app.PlayersCompanion.insert(
                      id: drift.Value(tempId),
                      teamId: teamIdInt,
                      name: nameCtrl.text,
                      defaultNumber: drift.Value(playerNum),
                      active: const drift.Value(true),
                      isSynced: const drift.Value(false),
                    ),
                  );
                  if (context.mounted) {context.showWarning("Sin conexión. Guardado localmente.");
                    Navigator.pop(ctx);
                  }
                } else {context.showError("Error: $e");}
              }
            },
            child: Text(isEditing ? "Actualizar" : "Guardar", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final db_app.Player player;
  const _PlayerCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final isLocal = (int.tryParse(player.id) ?? 0) < 0 || !player.isSynced;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.orangeAccent.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    "#${player.defaultNumber}",
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isLocal)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Pendiente de subir",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isLocal)
                const Tooltip(
                  message: "Guardado en dispositivo",
                  child: Icon(Icons.cloud_off, color: Colors.orangeAccent),
                )
              else
                const Tooltip(
                  message: "Sincronizado",
                  child: Icon(Icons.cloud_done, color: Colors.greenAccent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final teamPlayersStreamProvider =
    StreamProvider.family<List<db_app.Player>, int>((ref, teamId) {
      final db = ref.watch(di.databaseProvider);
      return (db.select(
        db.players,
      )..where((p) => p.teamId.equals(teamId))).watch();
    });
