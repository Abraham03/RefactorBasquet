// lib/ui/screens/starters_selection_screen.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:myapp/core/constants/app_colors.dart';
import 'package:myapp/ui/widgets/app_feedback.dart';

import '../core/database/app_database.dart' as db;
import '../core/di/dependency_injection.dart';
import '../core/models/catalog_models.dart' as catalog;
import 'match_control_screen.dart';
import '../ui/widgets/app_background.dart';
import '../../logic/starters_persistence_provider.dart';

class StartersSelectionScreen extends ConsumerStatefulWidget {
  final String matchId;
  final String? fixtureId;
  final catalog.Team teamA;
  final catalog.Team teamB;
  final List<catalog.Player> rosterA;
  final List<catalog.Player> rosterB;
  final int tournamentId;
  final int venueId;
  final String mainReferee;
  final String auxReferee;
  final String scorekeeper;
  final String tournamentName;
  final String categoryName;
  final String tournamentLogoUrl;
  final String refereeLogoUrl;
  final String venueName;

  const StartersSelectionScreen({
    super.key,
    required this.matchId,
    this.fixtureId,
    required this.teamA,
    required this.teamB,
    required this.rosterA,
    required this.rosterB,
    required this.tournamentId,
    required this.venueId,
    required this.mainReferee,
    required this.auxReferee,
    required this.scorekeeper,
    required this.tournamentName,
    required this.categoryName,
    required this.tournamentLogoUrl,
    required this.refereeLogoUrl,
    required this.venueName,
  });

  @override
  ConsumerState<StartersSelectionScreen> createState() =>
      _StartersSelectionScreenState();
}

class _StartersSelectionScreenState
    extends ConsumerState<StartersSelectionScreen> {
  
  late Set<int> _startersA;
  late Set<int> _startersB;
  int? _captainAId;
  int? _captainBId;
  
  bool _isCreating = false;
  late List<catalog.Player> _orderedRosterA;
  late List<catalog.Player> _orderedRosterB;

  @override
  void initState() {
    super.initState();
    // Clonamos las listas iniciales
    _orderedRosterA = List.from(widget.rosterA);
    _orderedRosterB = List.from(widget.rosterB);
    _sortRosters();

    final currentStarters = ref.read(selectedStartersProvider(widget.matchId));
    final currentCaptains = ref.read(selectedCaptainsProvider(widget.matchId));

    _startersA = Set<int>.from(currentStarters['A'] ?? {});
    _startersB = Set<int>.from(currentStarters['B'] ?? {});
    _captainAId = currentCaptains['A'];
    _captainBId = currentCaptains['B'];
  }

  void _sortRosters() {
    _orderedRosterA.sort((a, b) => a.defaultNumber.compareTo(b.defaultNumber));
    _orderedRosterB.sort((a, b) => a.defaultNumber.compareTo(b.defaultNumber));
  }

  void _syncWithProvider() {
    ref.read(selectedStartersProvider(widget.matchId).notifier).state = {
      'A': Set<int>.from(_startersA),
      'B': Set<int>.from(_startersB),
    };
    
    ref.read(selectedCaptainsProvider(widget.matchId).notifier).state = {
      'A': _captainAId,
      'B': _captainBId,
    };
  }

 // FALLO 1: Diferenciar entre Editar (Swap) y Crear + Anti-Deadlock
  Future<void> _refreshRosters() async {
    final dbBase = ref.read(databaseProvider);
    final api = ref.read(apiServiceProvider);

    try {
      final pending = await (dbBase.select(dbBase.players)..where((p) => p.isSynced.equals(false))).get();
      
      // --- TRUCO ANTI-DEADLOCK ---
      for (var p in pending) {
        final isExistingPlayer = (int.tryParse(p.id) ?? 0) > 0;
        if (isExistingPlayer) {
           try { await api.updatePlayer(p.id, p.teamId, p.name, p.defaultNumber + 1000); } catch (_) {}
        }
      }

      // --- SUBIDA FINAL ---
      for (var p in pending) {
        final isExistingPlayer = (int.tryParse(p.id) ?? 0) > 0;

        if (isExistingPlayer) {
          // Edición o Swap de un jugador existente
          final success = await api.updatePlayer(p.id, p.teamId, p.name, p.defaultNumber);
          if (success) {
            await (dbBase.update(dbBase.players)..where((tbl) => tbl.id.equals(p.id))).write(
              const db.PlayersCompanion(isSynced: drift.Value(true))
            );
          }
        } else {
          // Jugador totalmente nuevo creado offline
          final realId = await api.addPlayer(p.teamId, p.name, p.defaultNumber);
          await dbBase.transaction(() async {
             await (dbBase.update(dbBase.players)..where((tbl) => tbl.id.equals(p.id))).write(
               db.PlayersCompanion(id: drift.Value(realId.toString()), isSynced: const drift.Value(true))
             );
             await (dbBase.update(dbBase.gameEvents)..where((e) => e.playerId.equals(p.id))).write(
               db.GameEventsCompanion(playerId: drift.Value(realId.toString()))
             );
          });
        }
      }
    } catch (e) {
      debugPrint("Sincronización falló: $e");
    }

    final playersA = await (dbBase.select(dbBase.players)..where((p) => p.teamId.equals(widget.teamA.id))).get();
    final playersB = await (dbBase.select(dbBase.players)..where((p) => p.teamId.equals(widget.teamB.id))).get();

    setState(() {
      _orderedRosterA = playersA.map((p) => catalog.Player(id: int.tryParse(p.id) ?? -1, name: p.name, teamId: p.teamId, defaultNumber: p.defaultNumber, photoUrl: p.photoUrl)).toList();
      _orderedRosterB = playersB.map((p) => catalog.Player(id: int.tryParse(p.id) ?? -1, name: p.name, teamId: p.teamId, defaultNumber: p.defaultNumber, photoUrl: p.photoUrl)).toList();
      _sortRosters();
    });
  }

  void _showPlayerFormDialog(bool isTeamA, {catalog.Player? playerToEdit}) {
    final isEditing = playerToEdit != null;
    final nameController = TextEditingController(text: playerToEdit?.name ?? "");
    final numberController = TextEditingController(text: playerToEdit?.defaultNumber.toString() ?? "");
    final teamId = isTeamA ? widget.teamA.id : widget.teamB.id;
    final currentRoster = isTeamA ? _orderedRosterA : _orderedRosterB;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isEditing ? "Editar Jugador" : "Nuevo Jugador - ${isTeamA ? 'Local' : 'Visita'}", 
          style: const TextStyle(color: Colors.white, fontSize: 18)
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputStyle("Nombre Completo"),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 15),
            TextField(
              controller: numberController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputStyle("Número de Jersey"),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orangeAccent),
            onPressed: () async {
              final name = nameController.text.trim().toUpperCase();
              final number = int.tryParse(numberController.text) ?? -1;

              if (name.isEmpty || number == -1) return;

              final dbBase = ref.read(databaseProvider);
              
              // =================================================================
              // LÓGICA DE SWAP EN SELECCIÓN DE TITULARES
              // =================================================================
              final duplicates = currentRoster.where((p) => p.defaultNumber == number && p.id != playerToEdit?.id);
              
              if (duplicates.isNotEmpty) {
                final duplicatePlayer = duplicates.first;
                final numberForDuplicate = isEditing ? playerToEdit.defaultNumber : 0;
                
                final confirmSwap = await showDialog<bool>(
                  context: context,
                  builder: (swapCtx) => AlertDialog(
                    backgroundColor: AppColors.surfaceVariant,
                    title: const Text("🔄 Número Ocupado", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    content: Text(
                      "El jugador ${duplicatePlayer.name} ya usa el número $number.\n\n"
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

                if (confirmSwap != true) return;

                // Aplicar el swap en la base de datos (Queda offline pending de subir)
                await (dbBase.update(dbBase.players)..where((p) => p.id.equals(duplicatePlayer.id.toString()))).write(
                  db.PlayersCompanion(defaultNumber: drift.Value(numberForDuplicate), isSynced: const drift.Value(false))
                );
              }

              // =================================================================
              // GUARDAR AL JUGADOR PRINCIPAL
              // =================================================================
              if (isEditing) {
                // Actualizar
                await (dbBase.update(dbBase.players)..where((p) => p.id.equals(playerToEdit.id.toString()))).write(
                  db.PlayersCompanion(name: drift.Value(name), defaultNumber: drift.Value(number), isSynced: const drift.Value(false))
                );
              } else {
                // Crear Nuevo
                final tempId = (-DateTime.now().millisecondsSinceEpoch).toString();
                await dbBase.into(dbBase.players).insert(
                  db.PlayersCompanion.insert(
                    id: drift.Value(tempId),
                    name: name,
                    teamId: teamId, 
                    defaultNumber: drift.Value(number),
                    isSynced: const drift.Value(false),
                  )
                );
              }

              await _refreshRosters(); // Esto recargará y aplicará los cambios visualmente
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(isEditing ? "Actualizar" : "Guardar", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.black26,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.orangeAccent),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        extendBodyBehindAppBar: false, 
        backgroundColor: AppColors.background,
        appBar: AppBar(
          centerTitle: true,
          elevation: 0,
          backgroundColor: AppColors.surface,
          title: const Text("Titulares", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            indicatorColor: Colors.orangeAccent,
            indicatorWeight: 3,
            labelColor: Colors.orangeAccent,
            unselectedLabelColor: Colors.white38,
            tabs: [
              _buildTabItem(widget.teamA.name, true),
              _buildTabItem(widget.teamB.name, false),
            ],
          ),
        ),
        body: AppBackground(
          opacity: 0.4,
          child: Column(
            children: [
              Expanded(
                child: TabBarView(
                  // FALLO 2: Evitar selección múltiple involuntaria (física)
                  physics: const NeverScrollableScrollPhysics(), 
                  children: [
                    _buildSelectionList(_orderedRosterA, _startersA, Colors.orangeAccent, true),
                    _buildSelectionList(_orderedRosterB, _startersB, Colors.lightBlueAccent, false),
                  ],
                ),
              ),
              _buildBottomControlPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(String name, bool isTeamA) {
    return Tab(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(child: Text(name.toUpperCase(), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.person_add_alt_1, size: 18), onPressed: () => _showPlayerFormDialog(isTeamA)),
        ],
      ),
    );
  }



  Widget _buildSelectionList(List<catalog.Player> roster, Set<int> selectedIds, Color themeColor, bool isTeamA) {
  if (roster.isEmpty) {
    return const Center(
      child: Text(
        "No hay jugadores",
        style: TextStyle(color: Colors.white54, fontSize: 16, fontStyle: FontStyle.italic),
      ),
    );
  }

  return GridView.builder(
    padding: const EdgeInsets.all(16), // Padding ligeramente menor
    physics: const BouncingScrollPhysics(),
    // ===============================================================
    // 1. TARJETAS MÁS CHICAS
    // ===============================================================
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 160, // REDUCIDO DE 220 A 160 (Tarjetas más pequeñas)
      mainAxisSpacing: 16,    // Espaciado ajustado
      crossAxisSpacing: 16,
      childAspectRatio: 3 / 4.1, 
    ),
    itemCount: roster.length,
    itemBuilder: (context, index) {
      final player = roster[index];
      final isSelected = selectedIds.contains(player.id);
      final isCaptain = isTeamA ? _captainAId == player.id : _captainBId == player.id;

      String? resolvedPhotoUrl;
      if (player.photoUrl != null && player.photoUrl!.isNotEmpty) {
        resolvedPhotoUrl = player.photoUrl!.replaceAll('../', 'https://vanball.com.mx/');
      }

      return GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              selectedIds.remove(player.id);
              if (isCaptain) {
                if (isTeamA) {
                  _captainAId = null;
                } else {
                  _captainBId = null;
                }
              }
            } else if (selectedIds.length < 5) {
              selectedIds.add(player.id);
            }
          });
          _syncWithProvider();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: AppColors.surface, 
            borderRadius: BorderRadius.circular(20), // Borde un poco más suave
            border: Border.all(
              color: isSelected ? themeColor : Colors.white12,
              width: isSelected ? 3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected ? themeColor.withOpacity(0.4) : Colors.black38,
                blurRadius: isSelected ? 12 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17), 
            child: Stack(
              fit: StackFit.expand,
              children: [
                // FOTO DEL JUGADOR
                resolvedPhotoUrl != null
                    ? Image.network(
                        resolvedPhotoUrl,
                        fit: BoxFit.cover, 
                        alignment: Alignment.topCenter, 
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(color: themeColor.withOpacity(0.5), strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => _buildPlaceholderIcon(),
                      )
                    : _buildPlaceholderIcon(),

                // DEGRADADO INFERIOR
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withOpacity(0.4),
                          Colors.black.withOpacity(0.9),
                        ],
                        stops: const [0.0, 0.5, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),

                // ===============================================================
                // 2. NÚMERO SIEMPRE VISIBLE CON SOMBRA FUERTE
                // ===============================================================
                Positioned(
                  top: 8,
                  left: 8,
                  child: Text(
                    player.defaultNumber.toString(),
                    style: TextStyle(
                      fontSize: 48, // Ajustado al nuevo tamaño de tarjeta
                      fontWeight: FontWeight.w900,
                      color: isSelected ? Colors.white : Colors.white70, // Siempre visible
                      letterSpacing: -3,
                      height: 0.9,
                      shadows: const [
                        // Sombra oscura alrededor del número para que resalte sobre fondos blancos
                        Shadow(offset: Offset(2, 2), blurRadius: 4.0, color: Colors.black87),
                        Shadow(offset: Offset(-1, -1), blurRadius: 4.0, color: Colors.black87),
                      ],
                    ),
                  ),
                ),

                // CHECK DE SELECCIÓN
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(Icons.check_circle, color: themeColor, size: 26),
                  ),

                // BOTONES FLOTANTES (Estrella y Editar)
                Positioned(
                  top: isSelected ? 42 : 8, // Se ajusta si está el check
                  right: 8,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (!isSelected) return; 
                          setState(() { 
                            if (isTeamA) {
                              _captainAId = player.id;
                            } else {
                              _captainBId = player.id;
                            }
                          });
                          _syncWithProvider();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isCaptain ? Colors.amber : Colors.black54,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Icon(
                            isCaptain ? Icons.star : Icons.star_border, 
                            color: isCaptain ? Colors.black87 : Colors.white70,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _showPlayerFormDialog(isTeamA, playerToEdit: player),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(Icons.edit, color: Colors.white70, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),

                // NOMBRE DEL JUGADOR
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        player.name.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13, // Letra un poquito ajustada
                          letterSpacing: 0.5,
                          height: 1.1,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isCaptain)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "CAPITÁN",
                              style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// Icono por defecto (Un poco ajustado al nuevo tamaño)
Widget _buildPlaceholderIcon() {
  return Container(
    color: AppColors.surfacePlaceholder,
    child: Center(
      child: Icon(
        Icons.person,
        color: Colors.white.withOpacity(0.1),
        size: 80, 
      ),
    ),
  );
}

  Widget _buildBottomControlPanel() {
    bool canProceed = _startersA.length == 5 && _startersB.length == 5 && _captainAId != null && _captainBId != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), border: const Border(top: BorderSide(color: Colors.white24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTeamStatusColumn(widget.teamA.shortName, _startersA.length, _captainAId != null),
              _buildTeamStatusColumn(widget.teamB.shortName, _startersB.length, _captainBId != null),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              icon: _isCreating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.sports_basketball),
              label: Text(_isCreating ? "INICIANDO..." : "COMENZAR PARTIDO"),
              onPressed: (canProceed && !_isCreating) ? _startGame : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamStatusColumn(String name, int count, bool cap) {
    return Column(children: [
      Text(name.isEmpty ? "Equipo" : name, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
      Text("$count/5", style: TextStyle(color: count == 5 ? Colors.greenAccent : Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
      Text(cap ? "Capitán OK" : "Falta Capitán", style: TextStyle(color: cap ? Colors.greenAccent : Colors.redAccent, fontSize: 10)),
    ]);
  }

  Future<void> _startGame() async {
    setState(() => _isCreating = true);
    final matchDate = DateTime.now();
    
    try {
      final dbBase = ref.read(databaseProvider);
      final dao = ref.read(matchesDaoProvider);

      final existingMatch = await (dbBase.select(dbBase.matches)..where((t) => t.id.equals(widget.matchId))).getSingleOrNull();

      if (existingMatch == null) {
        await dbBase.into(dbBase.matches).insert(db.MatchesCompanion.insert(
          id: drift.Value(widget.matchId),
          fixtureId: drift.Value(widget.fixtureId),
          tournamentId: drift.Value(widget.tournamentId.toString()),
          venueId: drift.Value(widget.venueId.toString()),
          teamAName: widget.teamA.name,
          teamBName: widget.teamB.name,
          teamAId: drift.Value(widget.teamA.id),
          teamBId: drift.Value(widget.teamB.id),
          mainReferee: drift.Value(widget.mainReferee),
          auxReferee: drift.Value(widget.auxReferee),
          scorekeeper: drift.Value(widget.scorekeeper),
          status: const drift.Value('IN_PROGRESS'),
          matchDate: drift.Value(matchDate),
        ));
        await _saveRostersToDb(dao, dbBase);
      }

      if (widget.fixtureId != null) {
        await (dbBase.update(dbBase.fixtures)..where((t) => t.id.equals(widget.fixtureId!))).write(
          db.FixturesCompanion(status: const drift.Value('IN_PROGRESS'), matchId: drift.Value(widget.matchId))
        );
      }

      ref.invalidate(selectedStartersProvider(widget.matchId));
      ref.invalidate(selectedCaptainsProvider(widget.matchId));

      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => MatchControlScreen(
        matchId: widget.matchId,
        fixtureId: widget.fixtureId,
        teamAName: widget.teamA.name,
        teamBName: widget.teamB.name,
        tournamentId: widget.tournamentId,
        venueId: widget.venueId,
        teamAId: widget.teamA.id,
        teamBId: widget.teamB.id,
        mainReferee: widget.mainReferee,
        auxReferee: widget.auxReferee,
        scorekeeper: widget.scorekeeper,
        tournamentName: widget.tournamentName,
        categoryName: widget.categoryName,
        tournamentLogoUrl: widget.tournamentLogoUrl,
        refereeLogoUrl: widget.refereeLogoUrl,
        venueName: widget.venueName,
        fullRosterA: _orderedRosterA, // Usar las listas actualizadas
        fullRosterB: _orderedRosterB,
        startersAIds: _startersA,
        startersBIds: _startersB,
        coachA: widget.teamA.coachName,
        coachB: widget.teamB.coachName,
        captainAId: _captainAId,
        captainBId: _captainBId,
        matchDate: matchDate,
      )));
    } catch (e) {
      setState(() => _isCreating = false);
      context.showError("Error: $e");
    }
  }

  Future<void> _saveRostersToDb(dynamic dao, db.AppDatabase dbBase) async {
    List<db.MatchRostersCompanion> entries = [];
    for (var p in _orderedRosterA) {
      entries.add(db.MatchRostersCompanion.insert(
        matchId: widget.matchId, 
        playerId: p.id.toString(), 
        teamSide: 'A', 
        jerseyNumber: p.defaultNumber, 
        isCaptain: drift.Value(p.id == _captainAId),
        isStarter: drift.Value(_startersA.contains(p.id)),
        ));
    }
    for (var p in _orderedRosterB) {
      entries.add(db.MatchRostersCompanion.insert(
        matchId: widget.matchId, 
        playerId: p.id.toString(), 
        teamSide: 'B', 
        jerseyNumber: p.defaultNumber, 
        isCaptain: drift.Value(p.id == _captainBId),
        isStarter: drift.Value(_startersB.contains(p.id)),
        ));
    }
    await dao.addRosterToMatch(widget.matchId, entries);
  }
}