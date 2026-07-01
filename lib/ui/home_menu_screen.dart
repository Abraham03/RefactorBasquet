// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:myapp/core/di/dependency_injection.dart' show  syncRepositoryProvider;
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../core/database/app_database.dart';
import '../logic/tournament_provider.dart';
import '../logic/catalog_provider.dart';
import 'client_scoreboard_screen.dart';
import 'fixture_list_screen.dart';
import '../ui/match_setup_screen.dart';
import 'team_management_screen.dart';


import '../ui/widgets/glass_dashboard_card.dart';
import '../ui/widgets/app_background.dart';

import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:share_plus/share_plus.dart';
// <--- ESTE RECONOCE EL XFile
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';

import '../ui/widgets/app_feedback.dart';
import '../core/constants/app_colors.dart';

class HomeMenuScreen extends ConsumerStatefulWidget {
  const HomeMenuScreen({super.key});

  @override
  ConsumerState<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends ConsumerState<HomeMenuScreen> {
  bool _isAdminMode = false;
  int _tapCount = 0;

  void _toggleAdminMode() {
    setState(() {
      _tapCount++;
      if (_tapCount >= 5) {
        _isAdminMode = !_isAdminMode;
        _tapCount = 0;
        if (_isAdminMode) {
            context.showSuccess("Modo Administrador: ACTIVADO");
          } else {
            context.showInfo("Modo Administrador: DESACTIVADO");
          }
      }
    });
  }

  Future<void> _createNewTournament(String name, String category) async {
    final api = ref.read(apiServiceProvider);
    final db = ref.read(databaseProvider);
    String finalId = "";

    try {
      finalId = await api.createTournament(name, category);
      await db
          .into(db.tournaments)
          .insert(
            TournamentsCompanion.insert(
              id: drift.Value(finalId),
              name: name,
              category: drift.Value(category),
              status: const drift.Value('ACTIVE'),
              isSynced: const drift.Value(true),
            ),
          );

      if (mounted) {
        context.showSuccess("Torneo creado y sincronizado con la nube.");
      }
    } catch (e) {
      finalId = const Uuid().v4();
      await db
          .into(db.tournaments)
          .insert(
            TournamentsCompanion.insert(
              id: drift.Value(finalId),
              name: name,
              category: drift.Value(category),
              status: const drift.Value('ACTIVE'),
              isSynced: const drift.Value(false),
            ),
          );

      if (mounted) {
        context.showWarning("Torneo guardado localmente (Sin conexión).");
      }
    } finally {
      ref.read(selectedTournamentIdProvider.notifier).state = finalId;
      ref.invalidate(tournamentsListProvider);
      if (mounted) Navigator.pop(context);
    }
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final catCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "🏆 Nuevo Torneo",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: "Nombre del Torneo",
                  hintText: "Ej: Liga Municipal",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.emoji_events),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Este campo es requerido" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: catCtrl,
                decoration: InputDecoration(
                  labelText: "Categoría",
                  hintText: "Ej: Libre Varonil",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.category),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Este campo es requerido" : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                _createNewTournament(nameCtrl.text, catCtrl.text);
              }
            },
            child: const Text(
              "Crear Torneo",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- NUEVO: BOTTOM SHEET PARA DESCARGAR DESDE LA NUBE ---
  void _showCloudDownloadPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "Descargar desde la Nube",
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: ref.read(apiServiceProvider).fetchCloudTournaments(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Colors.purpleAccent));
                        }
                        if (snapshot.hasError) {
                          return const Center(child: Text("Error conectando al servidor", style: TextStyle(color: Colors.redAccent)));
                        }

                        final cloudTournaments = snapshot.data ?? [];

                        return ListView(
                          controller: scrollController,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            ListTile(
                              leading: const Icon(Icons.public, color: Colors.purpleAccent, size: 30),
                              title: const Text("Todos los Torneos", style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                              subtitle: const Text("Descargar la base de datos completa", style: TextStyle(color: Colors.white54, fontSize: 12)),
                              trailing: const Icon(Icons.cloud_download, color: Colors.purpleAccent),
                              onTap: () {
                                Navigator.pop(ctx);
                                _confirmSyncData("0", "Todos los Torneos"); // "0" significa descargar todo
                              },
                            ),
                            const Divider(color: Colors.white12),
                            if (cloudTournaments.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Center(child: Text("No hay torneos en la nube aún.", style: TextStyle(color: Colors.white54))),
                              ),
                            ...cloudTournaments.map((t) => ListTile(
                                  leading: const Icon(Icons.emoji_events, color: Colors.white70),
                                  title: Text(t['name'], style: const TextStyle(color: Colors.white)),
                                  subtitle: Text(t['category'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  trailing: const Icon(Icons.download, color: Colors.white38),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _confirmSyncData(t['id'].toString(), t['name']);
                                  },
                                )),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tournamentsAsync = ref.watch(tournamentsListProvider);
    final selectedTournamentId = ref.watch(selectedTournamentIdProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      floatingActionButton: _isAdminMode
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add),
              label: const Text("Nuevo Torneo"),
              backgroundColor: Colors.orange.withOpacity(0.80),
              foregroundColor: Colors.white,
            )
          : null,
      body: AppBackground(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final bool isWideScreen = constraints.maxWidth > 600;
                final int crossAxisCount = isWideScreen ? 4 : 2;
                final double contentWidth = isWideScreen ? 800 : double.infinity;

                return Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: _toggleAdminMode,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  color: Colors.transparent,
                                  padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 45,
                                        height: 45,
                                        decoration: BoxDecoration(
                                          color: Colors.white, // Fondo blanco para que el logo resalte
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.2),
                                              blurRadius: 5,
                                              offset: const Offset(0, 3),
                                            )
                                          ],
                                          image: const DecorationImage(
                                            image: AssetImage('assets/images/app_logo.png'), // Tu ruta exacta
                                            fit: BoxFit.contain, // Ajusta la imagen dentro del círculo
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 15),
                                      const Text(
                                        "Van Ball",
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      if (_isAdminMode) ...[
                                        const SizedBox(width: 10),
                                        const Icon(
                                          Icons.admin_panel_settings,
                                          size: 20,
                                          color: Colors.orangeAccent,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                "Espacio de Trabajo Local:", // <--- Cambio aquí
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 8),

                              tournamentsAsync.when(
                                loading: () => const SizedBox(
                                  height: 20, width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                ),
                                error: (err, stack) => const Text("Error cargando torneos", style: TextStyle(color: Colors.redAccent)),
                                data: (tournaments) {
                                  
                                  // Ya no mostramos un simple texto, mostramos siempre la tarjeta visual
                                  // Si está vacía o es "0", dirá "Todos los Torneos"
                                  final selectedName = (selectedTournamentId == "0" || selectedTournamentId == null)
                                      ? "Todos los Torneos"
                                      : tournaments.firstWhere(
                                          (t) => t.id == selectedTournamentId,
                                          orElse: () => tournaments.first, //usamos tournaments.first
                                        ).name;

                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                      child: Material(
                                        color: Colors.white.withOpacity(0.15),
                                        child: InkWell(
                                          onTap: () => _showLocalTournamentPicker(
                                            context,
                                            tournaments,
                                            ref,
                                            selectedTournamentId,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(15),
                                              border: Border.all(color: Colors.white.withOpacity(0.3)),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    selectedName,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.keyboard_arrow_down,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            child: GridView.count(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: isWideScreen ? 1.3 : 1.05,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                GlassDashboardCard(
                                    title: "Calendario",
                                    icon: Icons.calendar_month,
                                    color: Colors.tealAccent,
                                    onTap: selectedTournamentId == null || selectedTournamentId == "0"
                                        ? () => _showNoTournamentAlert(context)
                                        : () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => FixtureListScreen(tournamentId: selectedTournamentId),
                                            ),
                                          ),
                                  ),
                                GlassDashboardCard(
                                  title: "Jugar Partido",
                                  icon: Icons.sports_basketball,
                                  color: Colors.orange,
                                  onTap: () {
                                    if (selectedTournamentId == null || selectedTournamentId == "0") {
                                      _showNoTournamentAlert(context);
                                      return;
                                    }
                                    
                                    // 🔒 BLOQUEO AMIGABLE 1: Evitar que entren con un Torneo Offline
                                    final numericId = int.tryParse(selectedTournamentId);
                                    if (numericId == null || numericId < 0) {
                                      context.showWarning("Torneo Local. Súbelo a la nube antes de jugar un partido oficial.");
                                      return; // Aborta la navegación
                                    }

                                    // Si pasa la validación, navega normal
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MatchSetupScreen(tournamentId: selectedTournamentId),
                                      ),
                                    );
                                  },
                                ),
                                if (_isAdminMode) ...[
                                  GlassDashboardCard(
                                    title: "Pantalla Tablero",
                                    icon: Icons.tv,
                                    color: Colors.deepPurpleAccent,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ClientScoreboardScreen()),
                                    ),
                                  ),
                                  GlassDashboardCard(
                                    title: "Equipos",
                                    icon: Icons.groups,
                                    color: Colors.blueAccent,
                                    onTap: selectedTournamentId == null || selectedTournamentId == "0"
                                        ? () => _showNoTournamentAlert(context)
                                        : () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TeamManagementScreen(tournamentId: selectedTournamentId),
                                            ),
                                          ),
                                  ),
                                  GlassDashboardCard(
                                  title: "Descargar Datos",
                                  icon: Icons.cloud_download,
                                  color: Colors.purpleAccent,
                                  onTap: () => _showCloudDownloadPicker(), // <- AHORA ABRE EL MENÚ DE LA NUBE
                                ),
                                GlassDashboardCard(
                                  title: "Subir a Nube",
                                  icon: Icons.cloud_upload,
                                  color: Colors.greenAccent,
                                  onTap: () => _uploadPendingData(),
                                ),
                                GlassDashboardCard(
                                    title: "Ver SQLite Local",
                                    icon: Icons.storage,
                                    color: Colors.redAccent,
                                    onTap: () {
                                      // Obtenemos la instancia de la base de datos
                                      final db = ref.read(databaseProvider);
                                      // Navegamos al visor mágico
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => DriftDbViewer(db),
                                        ),
                                      );
                                    },
                                  ),
                                  GlassDashboardCard(
                                    title: "Rescatar Partido",
                                    icon: Icons.bug_report,
                                    color: Colors.orangeAccent,
                                    onTap: () => _showRescueMatchPicker(),
                                  ),
                                ],
                                
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 20,
              left: 20,
              child: GestureDetector(
                onTap: _toggleAdminMode,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(color: Colors.transparent),
                ),
              ),
            ),
            const Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: AppVersionDisplay(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SELECTOR LOCAL (Ajustado con Categoría) ---
  void _showLocalTournamentPicker(
    BuildContext context,
    List<dynamic> tournaments,
    WidgetRef ref,
    String? currentId,
  ) {
    // Convertimos a Map para inyectar "Todos los Torneos" sin errores de modelo,
    // agregando también el campo de "category".
    List<Map<String, dynamic>> extendedList = [
      {"id": "0", "name": "Todos los Torneos", "category": "Base de datos completa"}
    ];
    for (var t in tournaments) {
      extendedList.add({
        "id": t.id.toString(), 
        "name": t.name,
        "category": t.category ?? 'Libre' // Añadimos la categoría aquí
      });
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  width: 40, height: 5,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(5)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text("Cambiar de Torneo (Offline)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: extendedList.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = extendedList[index];
                      final isSelected = item["id"] == (currentId ?? "0");
                      final isAllOption = item["id"] == "0";

                      return ListTile(
                        leading: Icon(
                          isAllOption ? Icons.public : Icons.emoji_events,
                          color: isSelected ? Colors.orange : Colors.grey,
                        ),
                        title: Text(
                          item["name"],
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.orange : (isAllOption ? Colors.black : Colors.black87),
                          ),
                        ),
                        // AQUÍ AGREGAMOS EL SUBTITLE PARA MOSTRAR LA CATEGORÍA
                        subtitle: Text(
                          item["category"],
                          style: TextStyle(
                            color: isAllOption ? Colors.black45 : Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.orange) : null,
                        onTap: () {
                          ref.read(selectedTournamentIdProvider.notifier).state = item["id"];
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNoTournamentAlert(BuildContext context) {
    context.showInfo("Por favor, selecciona un torneo específico arriba para continuar.");
  }

  // --- MODIFICADO: AHORA RECIBE EL ID DIRECTO DESDE EL MENÚ DE LA NUBE ---
  Future<void> _syncData(String syncId) async {
    final db = ref.read(databaseProvider);

    // ====================================================================
    // --- 1. VERIFICACIÓN Y DIÁLOGO DE ADVERTENCIA ---
    // ====================================================================
    final pendingMatches = await (db.select(db.matches)..where((m) => m.isSynced.equals(false))).get();
    
    if (pendingMatches.isNotEmpty) {
      // Mostrar diálogo de confirmación si hay datos en riesgo
      final bool? confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false, // Obliga al usuario a elegir una opción
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text("¡Peligro de pérdida de datos!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ],
          ),
          content: const Text(
            "Tienes partidos pendientes por subir a la nube. Si descargas los datos ahora, SE BORRARÁN TODOS TUS PARTIDOS LOCALES y perderás esa información de forma permanente.\n\n¿Estás completamente seguro de querer continuar y eliminar los datos no subidos?",
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Sí, borrar y descargar", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      // Si el usuario presionó "Cancelar" o cerró el diálogo de alguna forma
      if (confirm != true) {
        return; 
      }
    }

    // ====================================================================
    // --- 2. INICIO DE LA DESCARGA ---
    // ====================================================================
    context.showInfo("Sincronizando datos... por favor espera.");

    try {
      final api = ref.read(apiServiceProvider);
      final catalogData = await api.fetchCatalogs(syncId);

      await db.transaction(() async {
        // ====================================================================
        // --- 3. LIMPIEZA ABSOLUTA DE FANTASMAS Y DATOS LOCALES ---
        // ====================================================================
        // Al descargar, borramos todo el historial local para que quede idéntico a la nube
        await db.delete(db.matchRosters).go(); // NUEVO
        await db.delete(db.gameEvents).go();   // NUEVO
        await db.delete(db.matches).go();      // NUEVO
        
        await db.delete(db.tournaments).go();
        await db.delete(db.teams).go();
        await db.delete(db.players).go();
        await db.delete(db.tournamentTeams).go();
        await db.delete(db.venues).go();
        await db.delete(db.fixtures).go();
        await db.delete(db.officials).go();

        // --- INSERCIONES DE CATÁLOGOS ---
        for (var t in catalogData.tournaments) {
          await db.into(db.tournaments).insert(
                TournamentsCompanion.insert(
                  id: drift.Value(t.id.toString()),
                  name: t.name,
                  category: drift.Value(t.category),
                  status: drift.Value(t.status ?? 'ACTIVE'),
                  logoUrl: drift.Value(t.logoUrl),
                  refereeLogoUrl: drift.Value(t.refereeLogoUrl),
                  isSynced: const drift.Value(true),
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
        }

        for (var m in catalogData.fixturesRaw) {
          DateTime? scheduledDate;
          if (m['scheduled_datetime'] != null && m['scheduled_datetime'].toString().isNotEmpty) {
            scheduledDate = DateTime.tryParse(m['scheduled_datetime'].toString());
          }
          int? sA, sB;
          if (m['score_a'] != null) sA = int.tryParse(m['score_a'].toString());
          if (m['score_b'] != null) sB = int.tryParse(m['score_b'].toString());

          await db.into(db.fixtures).insert(
                FixturesCompanion.insert(
                  id: m['id'].toString(),
                  tournamentId: m['tournament_id'].toString(),
                  roundName: m['round_name'] ?? 'Jornada',
                  teamAId: m['team_a_id'].toString(),
                  teamBId: m['team_b_id'].toString(),
                  teamAName: m['team_a'] ?? 'Equipo A',
                  teamBName: m['team_b'] ?? 'Equipo B',
                  logoA: drift.Value(m['logo_a']),
                  logoB: drift.Value(m['logo_b']),
                  venueId: drift.Value(m['venue_id']?.toString()),
                  venueName: drift.Value(m['venue_name']),
                  scheduledDatetime: drift.Value(scheduledDate),
                  matchId: drift.Value(m['match_id']?.toString()),
                  scoreA: drift.Value(sA),
                  scoreB: drift.Value(sB),
                  status: drift.Value(m['status'] ?? 'SCHEDULED'),
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
        }

        for (var team in catalogData.teams) {
          await db.into(db.teams).insert(
                TeamsCompanion.insert(
                  id: drift.Value(team.id.toString()),
                  name: team.name,
                  shortName: drift.Value(team.shortName),
                  coachName: drift.Value(team.coachName),
                  logoUrl: drift.Value(team.logoUrl),
                  isSynced: const drift.Value(true),
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
        }

        for (var venue in catalogData.venues) {
          await db.into(db.venues).insert(
                VenuesCompanion.insert(
                  id: drift.Value(venue.id.toString()),
                  name: venue.name,
                  address: drift.Value(venue.address),
                  isSynced: const drift.Value(true),
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
        }

        for (var rel in catalogData.relationships) {
          await db.into(db.tournamentTeams).insert(
                TournamentTeamsCompanion.insert(
                  tournamentId: rel.tournamentId.toString(),
                  teamId: rel.teamId.toString(),
                  isSynced: const drift.Value(true),
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
        }

        for (var p in catalogData.players) {
          await db.into(db.players).insert(
                PlayersCompanion.insert(
                  id: drift.Value(p.id.toString()),
                  name: p.name,
                  teamId: p.teamId,
                  defaultNumber: drift.Value(p.defaultNumber),
                  active: const drift.Value(true),
                  isSynced: const drift.Value(true),
                  photoUrl: drift.Value(p.photoUrl),
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
        }

       for (var off in catalogData.officials) { 
          await db.into(db.officials).insert(
            OfficialsCompanion.insert(
              id: off.id.toString(), 
              name: off.name,
              role: drift.Value(off.role),
              signatureData: drift.Value(off.signature),
              active: const drift.Value(true), 
              isSynced: const drift.Value(true),
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
        }
      });

      // Actualizamos el selector de la UI al torneo que acabamos de descargar
      ref.read(selectedTournamentIdProvider.notifier).state = syncId;
      ref.invalidate(tournamentsListProvider);

      if (context.mounted) {
        context.showSuccess("Datos descargados y actualizados con éxito.");
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_off, color: Colors.redAccent, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text("Sin conexión al servidor", 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)
                  ),
                ),
              ],
            ),
            content: const Text(
              "No pudimos descargar los datos de la nube en este momento.\n\nPor favor, verifica tu conexión a internet o inténtalo más tarde. Tus datos locales están seguros y puedes seguir operando sin conexión.",
              style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("Entendido", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _uploadPendingData() async {
    final loading = context.showLoading("Subiendo datos a la nube...");

    try {
      final result = await ref.read(syncRepositoryProvider).uploadPendingData();

      if (result.needsRedownload) {
        await _syncData("0");
      } else {
        ref.invalidate(tournamentsListProvider);
      }

      if (context.mounted) {
        loading.close();
        context.showSuccess("☁️ Sincronización exitosa.\n${result.toSummary()}");
        if (result.hasSkipped) {
          context.showWarning(
              "Partidos omitidos (jugadores sin sincronizar): ${result.skippedMatches.join(', ')}");
        }
      }
    } catch (e) {
      if (context.mounted) {
        loading.close();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sync_problem, color: Colors.orange, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text("Problema al Subir",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
                ),
              ],
            ),
            content: const Text(
              "Tuvimos un inconveniente al intentar respaldar tus datos en la nube.\n\nPor favor, revisa tu conexión a internet e inténtalo nuevamente. No te preocupes, toda tu información sigue guardada localmente de forma segura.",
              style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("Entendido", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> exportMatchToJSON(String matchId) async {
    final db = ref.read(databaseProvider);
    
    // 1. Buscamos el partido base y el fixture
    final match = await (db.select(db.matches)
      ..where((t) => t.id.equals(matchId))
      ..where((t) => t.isSynced.equals(false)))
    .getSingle();
    final fixtureRow = match.fixtureId != null 
        ? await (db.select(db.fixtures)..where((f) => f.id.equals(match.fixtureId!))).getSingleOrNull() 
        : null;

    // =================================================================
    // 2. OBTENER EVENTOS (Con JOIN para sacar nombres, números y lados)
    // =================================================================
    final query = db.select(db.gameEvents).join([
      drift.leftOuterJoin(
        db.matchRosters,
        db.matchRosters.matchId.equalsExp(db.gameEvents.matchId) &
            db.matchRosters.playerId.equalsExp(db.gameEvents.playerId),
      ),
      drift.leftOuterJoin(
        db.players,
        db.players.id.equalsExp(db.gameEvents.playerId),
      ),
    ]);
    query.where(db.gameEvents.matchId.equals(match.id));
    final rows = await query.get();
    
    int runningScoreA = 0;
    int runningScoreB = 0;
    
    final eventsList = rows.map((row) {
      final event = row.readTable(db.gameEvents);
      final roster = row.readTableOrNull(db.matchRosters);
      final player = row.readTableOrNull(db.players);
      
      String rawType = event.type;
      String teamSide = roster?.teamSide ?? 'A';
      if (rawType.endsWith('_A')) {
        teamSide = 'A';
        rawType = rawType.replaceAll('_A', '');
      } else if (rawType.endsWith('_B')) {
        teamSide = 'B';
        rawType = rawType.replaceAll('_B', '');
      }
      
      int points = 0;
      if (rawType == 'POINT_1' || rawType == 'FREE_THROW') points = 1;
      if (rawType == 'POINT_2') points = 2;
      if (rawType == 'POINT_3') points = 3;
      
      bool isTeamA = teamSide == 'A';
      if (points > 0) {
        if (isTeamA) {
          runningScoreA += points;
        } else {
          runningScoreB += points;
        }
      }
      final currentScore = isTeamA ? runningScoreA : runningScoreB;
      
      // Manejo seguro del ID del jugador (Detectar negativos)
      int? pId;
      if (event.playerId != null && event.playerId!.isNotEmpty && event.playerId != '-1') {
        pId = int.tryParse(event.playerId!);
      }

      return {
        "period": event.period,
        "team_side": teamSide,
        "player_name": player?.name ?? '',
        "player_id": pId, // Mandará el número negativo si es offline, para que lo cambies manual en Postman
        "player_number": roster?.jerseyNumber ?? 0,
        "points_scored": points,
        "score_after": currentScore,
        "type": rawType,
      };
    }).toList();

    // =================================================================
    // 3. OBTENER ROSTERS (Listas de jugadores del partido)
    // =================================================================
    final rosterRows = await (db.select(db.matchRosters)..where((r) => r.matchId.equals(match.id))).get();
    final rostersList = rosterRows.map((r) {
      final pIdInt = int.tryParse(r.playerId) ?? 0;
      bool hasPlayed = eventsList.any((event) => event["player_id"] == pIdInt);
      return {
        "player_id": pIdInt,
        "team_side": r.teamSide,
        "jersey_number": r.jerseyNumber,
        "is_captain": r.isCaptain ? 1 : 0,
        "played": hasPlayed ? 1 : 0
      };
    }).toList();

    // Formatear Fecha
    String formattedDate = "";
    if (match.matchDate != null) {
      final d = match.matchDate!;
      formattedDate = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}";
    }

    // =================================================================
    // 4. ESTRUCTURA MAESTRA (Idéntica a la que pide tu API)
    // =================================================================
    final Map<String, dynamic> exportData = {
      "match_id": match.id,
      "fixture_id": fixtureRow?.id,
      "tournament_id": match.tournamentId,
      "venue_id": match.venueId,
      "team_a_id": match.teamAId,
      "team_b_id": match.teamBId,
      "team_a_name": match.teamAName,
      "team_b_name": match.teamBName,
      "score_a": match.scoreA,
      "score_b": match.scoreB,
      "current_period": 4, 
      "time_left": "00:00",
      "main_referee": match.mainReferee,
      "aux_referee": match.auxReferee,
      "scorekeeper": match.scorekeeper,
      "forfeit_status": "NONE",
      "observaciones": "",
      "match_date": formattedDate,
      "signature_base64": match.signatureData,
      "status": match.status,
      "events": eventsList,
      "rosters": rostersList,
    };

    // Convertimos a String para el portapapeles
    String jsonString = jsonEncode(exportData);
    
    // =================================================================
    // 5. MANEJO DEL PDF Y ENVÍO POR SHARE (Solución Doble Archivo)
    // =================================================================
    String? pdfPath = match.matchReportPath;
    bool pdfExists = false;
    
    if (pdfPath != null && pdfPath.isNotEmpty) {
      pdfExists = await File(pdfPath).exists();
    }

    // 1. Convertir el texto JSON en un archivo físico (.txt) temporal
    final tempDir = Directory.systemTemp;
    final jsonFile = File('${tempDir.path}/json_rescate_${match.id}.txt');
    await jsonFile.writeAsString(jsonString);

    if (pdfExists) {
      // 2A. Compartimos AMBOS archivos: El PDF y el TXT
      await Share.shareXFiles(
        [
          XFile(pdfPath!), 
          XFile(jsonFile.path) // Mandamos el archivo físico del JSON
        ], 
        subject: 'Rescate Partido ${match.teamAName} vs ${match.teamBName}',
        text: 'Adjunto PDF del acta y archivo TXT con los datos JSON.',
      );
    } else {
      // 2B. Si no hay PDF, mandamos de todos modos el archivo TXT
      await Share.shareXFiles(
        [XFile(jsonFile.path)], 
        subject: 'Rescate Partido (Sin PDF) ${match.teamAName} vs ${match.teamBName}',
        text: 'Este partido no tiene PDF generado. Adjunto el archivo TXT con el JSON.',
      );
    }
  }

  // --- NUEVO: MENÚ DE RESCATE DE PARTIDOS ATASCADOS ---
  void _showRescueMatchPicker() async {
    final db = ref.read(databaseProvider);
    
    // Buscamos SOLO los partidos que NO se han podido subir a la nube
    final pendingMatches = await (db.select(db.matches)..where((m) => m.isSynced.equals(false))).get();

    if (!mounted) return;

    if (pendingMatches.isEmpty) {
      context.showSuccess("No hay partidos atascados.");
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40, height: 5,
              decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(10)),
            ),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Rescatar Partido (Exportar JSON)", 
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pendingMatches.length,
                itemBuilder: (context, index) {
                  final match = pendingMatches[index];
                  return ListTile(
                    leading: const Icon(Icons.bug_report, color: Colors.redAccent),
                    title: Text("${match.teamAName} vs ${match.teamBName}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text("ID: ${match.id}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: const Icon(Icons.share, color: Colors.orangeAccent),
                    onTap: () {
                      Navigator.pop(ctx);
                      // AQUÍ ES DONDE MANDAMOS A LLAMAR TU FUNCIÓN
                      exportMatchToJSON(match.id); 
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _confirmSyncData(String syncId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text("Confirmar Descarga", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Estás a punto de descargar los datos de '$name'.\n\n⚠️ ¡Atención! Esto reemplazará toda tu base de datos local actual con la información de la nube. Cualquier dato no subido se perderá.\n\n¿Deseas continuar?", 
          style: const TextStyle(color: Colors.white70, height: 1.4)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey))
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orangeAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _syncData(syncId);
            },
            child: const Text("Sí, descargar", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class AppVersionDisplay extends StatelessWidget {
  const AppVersionDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final version = snapshot.data!.version;
        final buildNumber = snapshot.data!.buildNumber;
        
        return Text(
          "Van Ball v$version (Build $buildNumber)",
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3), // Color muy sutil
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
          textAlign: TextAlign.center,
        );
      },
    );
  }
}