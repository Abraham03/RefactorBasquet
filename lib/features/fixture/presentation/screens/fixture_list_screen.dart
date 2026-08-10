// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:myapp/core/constants/app_colors.dart';
import 'package:myapp/features/scoreboard/presentation/providers/scoreboard_providers.dart';
import 'package:myapp/features/match/presentation/screens/attendance_edit_screen.dart';
import 'package:myapp/shared/widgets/app_feedback.dart'; 
import 'package:myapp/features/catalog/domain/entities/catalog_models.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/di/providers.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';
import 'package:myapp/features/match/presentation/screens/match_setup_screen.dart';
import 'package:myapp/features/match/presentation/screens/match_control_screen.dart';
import 'package:myapp/shared/widgets/app_background.dart';
import 'package:myapp/shared/widgets/app_network_image.dart';
import 'package:myapp/features/fixture/presentation/screens/manual_fixture_builder_screen.dart';
import 'package:myapp/features/fixture/presentation/widgets/tournament_rules_dialog.dart';
import 'package:myapp/features/match/presentation/screens/change_outcome_screen.dart';           // ChangeOutcomeScreen
import 'package:myapp/features/match/domain/services/outcome_changer.dart'; // OutcomePdfParams
import 'package:myapp/core/network/connectivity_helper.dart';
import 'package:myapp/features/fixture/presentation/providers/fixture_providers.dart';
import 'package:myapp/core/errors/app_exception.dart';
import 'package:myapp/core/network/result.dart';

/// Desenvuelve un [Result] o relanza su error tipado.
///
/// Estas pantallas ya envolvian las llamadas en `try/catch`; relanzar preserva
/// ese flujo y sustituye el viejo `Exception('texto')` por una `AppException`
/// con su causa.
T _unwrapOrThrow<T>(Result<T> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw error,
};

class FixtureListScreen extends ConsumerStatefulWidget {
  final String tournamentId;
  const FixtureListScreen({super.key, required this.tournamentId});

  @override
  ConsumerState<FixtureListScreen> createState() => _FixtureListScreenState();
}

class _FixtureListScreenState extends ConsumerState<FixtureListScreen> {
  // Lo dejamos nulo inicialmente para poder asignarle la Jornada 1 de forma automática al cargar
  String? _selectedRound;

  // --- HELPER PARA TEXTO DE ENFRENTAMIENTO ---
  String _getEncounterText(int count) {
    switch (count) {
      case 1: return "1er Encuentro";
      case 2: return "2do Encuentro";
      case 3: return "3er Encuentro";
      case 4: return "4to Encuentro";
      case 5: return "5to Encuentro";
      case 6: return "6to Encuentro";
      default: return "$countº Encuentro";
    }
  }

  // --- BOTTOM SHEET DE OPCIONES DE GENERACIÓN ---
  void _showGenerationOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2432),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Creación de Calendario", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text("Elige cómo deseas programar los partidos de este torneo.", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.white.withValues(alpha: 0.05),
              leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.auto_awesome, color: Colors.white)),
              title: const Text("Generación Automática", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("Crea todas las jornadas y cruza a todos los equipos usando el método de Round Robin.", style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _generateNewFixture(context); 
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.white.withValues(alpha: 0.05),
              leading: const CircleAvatar(backgroundColor: Colors.orangeAccent, child: Icon(Icons.edit_calendar, color: Colors.black)),
              title: const Text("Constructor Manual", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("Crea jornadas y programa partidos uno por uno, ideal para torneos en progreso.", style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ManualFixtureBuilderScreen(tournamentId: widget.tournamentId)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- BOTTOM SHEET DE FILTRO DE JORNADAS ---
  void _showRoundsFilterBottomSheet(List<String> rounds, String currentActiveRound) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.45, 
              decoration: BoxDecoration(
                color: const Color(0xFF1E2432).withValues(alpha: 0.9), 
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
                      "Filtrar por Jornada",
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: rounds.length,
                      itemBuilder: (context, index) {
                        final round = rounds[index];
                        final isSelected = round == currentActiveRound;
                        
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                          tileColor: isSelected ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.transparent,
                          title: Text(
                            round.toUpperCase(),
                            style: TextStyle(
                              color: isSelected ? Colors.orangeAccent : Colors.white70,
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal,
                              fontSize: 16,
                              letterSpacing: 1.0,
                            ),
                          ),
                          trailing: isSelected 
                              ? const Icon(Icons.check_circle, color: Colors.orangeAccent) 
                              : null,
                          onTap: () {
                            Navigator.pop(ctx); 
                            if (round != currentActiveRound) {
                              setState(() => _selectedRound = round); 
                            }
                          },
                        );
                      },
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

  Future<void> _generateNewFixture(BuildContext context) async {
    final rules = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const TournamentRulesDialog(showVueltas: true),
    );

    if (rules == null || !mounted) return;

    // Si ya hay calendario local, confirmamos antes de sobrescribir.
    final db = ref.read(databaseProvider);
    final existing = await (db.select(db.fixtures)
          ..where((f) => f.tournamentId.equals(widget.tournamentId)))
        .get();

    if (existing.isNotEmpty) {
      if (!mounted) return;
      final confirm = await _confirmOverwrite(context);
      if (confirm != true) return;
    }

    if (!mounted) return;
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
    ));

    try {
      final catalogApi = ref.read(catalogApiProvider);
      final api = ref.read(fixtureApiProvider);

      // 1. Guardar reglas
      final rulesSaved = (await catalogApi.saveTournamentRules(
        tournamentId: widget.tournamentId,
        vueltas: rules['vueltas'],
        ptsVictoria: rules['win'],
        ptsDerrota: rules['loss'],
        ptsEmpate: rules['draw'],
        ptsForfeitWin: rules['forfeitWin'],
        ptsForfeitLoss: rules['forfeitLoss'],
      )).isOk;
      if (!rulesSaved) throw Exception("Error guardando las reglas del torneo");

      // 2. Si había calendario, purgamos en el servidor ANTES de regenerar.
      //    Esto evita el bloqueo "ya existen partidos" al dejar la tabla limpia.
      if (existing.isNotEmpty) {
        final purge = await api.deleteFixture(tournamentId: widget.tournamentId);
        if (purge case Err(:final error)) {
          throw Exception(error.message);
        }
      }

      // 3. Generar
      final result = await api.generateFixture(tournamentId: widget.tournamentId);
      if (result case Err(:final error)) {
        // Mensaje REAL del servidor (regla de negocio, etc.): ahora llega en
        // ApiBusinessException.message sin pasar por un ApiResult a medida.
        throw Exception(error.message);
      }

      // 4. Descargar y persistir localmente el nuevo calendario
      final newFixtureData = (await api.fetchFixture(widget.tournamentId)).valueOrNull ?? {};
      if (newFixtureData.isNotEmpty && newFixtureData['rounds'] != null) {
        await (db.delete(db.fixtures)..where((f) => f.tournamentId.equals(widget.tournamentId))).go();

        final roundsMap = newFixtureData['rounds'] as Map<String, dynamic>;
        await db.transaction(() async {
          for (var entry in roundsMap.entries) {
            final roundName = entry.key;
            for (var m in (entry.value as List)) {
              await db.into(db.fixtures).insert(
                FixturesCompanion.insert(
                  id: m['id'].toString(),
                  tournamentId: widget.tournamentId,
                  roundName: roundName,
                  teamAId: m['team_a_id'].toString(),
                  teamBId: m['team_b_id'].toString(),
                  teamAName: m['team_a'] ?? 'A',
                  teamBName: m['team_b'] ?? 'B',
                  logoA: drift.Value(m['logo_a']),
                  logoB: drift.Value(m['logo_b']),
                  status: drift.Value(m['status'] ?? 'SCHEDULED'),
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
            }
          }
        });

        ref.invalidate(localFixtureProvider(widget.tournamentId));
        setState(() => _selectedRound = null);
      }

      if (!mounted) return;
      Navigator.pop(context);
      context.showSuccess("Calendario generado con éxito");
    } on AppException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      // El mensaje ya viene listo para el usuario. Antes habia que limpiar a
      // mano el prefijo "Exception: " que Dart anade al envolver strings.
      context.showError(e.message);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      context.showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool?> _confirmOverwrite(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text("Sobrescribir calendario",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
        content: const Text(
          "Ya existe un calendario para este torneo. Regenerarlo borrará el calendario actual y los partidos asociados en el servidor.\n\n¿Deseas continuar?",
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
            child: const Text("Sí, sobrescribir", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showFinishedMatchOptions(BuildContext context, dynamic match) {
    final matchId = match.matchId ?? match.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text("${match.teamAName} vs ${match.teamBName}",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const Divider(height: 1, color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.how_to_reg, color: AppColors.primary),
              title: const Text("Corregir asistencia", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AttendanceEditScreen(
                    matchId: matchId,
                    teamAName: match.teamAName,
                    teamBName: match.teamBName,
                  ),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.gavel, color: Colors.orangeAccent),
              title: const Text("Cambiar resultado", style: TextStyle(color: Colors.white)),
              subtitle: const Text("Forfeit, protesta o normal", style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseProvider);

              // 1. Intentar fila matches local (solo existe si el partido se jugó aquí).
              final linkedId = match.matchId;
              var localMatch = (linkedId != null && linkedId.isNotEmpty)
                  ? await (db.select(db.matches)..where((t) => t.id.equals(linkedId))).getSingleOrNull()
                  : null;
              localMatch ??= await (db.select(db.matches)
                    ..where((t) => t.fixtureId.equals(match.id))).getSingleOrNull();

              // Datos del acta: si no hay fila local, los traemos del backend.
              // Variables que usaremos para armar OutcomePdfParams.
              String actaMatchId;
              String actaTeamAName, actaTeamBName;
              String actaMainReferee, actaAuxReferee, actaScorekeeper;
              DateTime? actaMatchDate;
              String? actaTournamentId;
              int actaTeamAId, actaTeamBId;
              String? actaVenueId;

              if (localMatch != null) {
                // Acta local disponible (partido jugado en este dispositivo).
                actaMatchId = localMatch.id;
                actaTeamAName = localMatch.teamAName;
                actaTeamBName = localMatch.teamBName;
                actaMainReferee = localMatch.mainReferee ?? '';
                actaAuxReferee = localMatch.auxReferee ?? '';
                actaScorekeeper = localMatch.scorekeeper ?? '';
                actaMatchDate = localMatch.matchDate;
                actaTournamentId = localMatch.tournamentId;
                actaTeamAId = localMatch.teamAId ?? 0;
                actaTeamBId = localMatch.teamBId ?? 0;
                actaVenueId = localMatch.venueId;
              } else {
                // Sin acta local: traer del backend (online-only).
                final remoteId = match.matchId ?? match.id;
                try {
                  final api = ref.read(matchApiProvider);
                  final details = _unwrapOrThrow(await api.getMatchDetails(remoteId));
                  actaMatchId = details['id']?.toString() ?? remoteId;
                  actaTeamAName = details['team_a_name']?.toString() ?? match.teamAName;
                  actaTeamBName = details['team_b_name']?.toString() ?? match.teamBName;
                  actaMainReferee = details['main_referee']?.toString() ?? '';
                  actaAuxReferee = details['aux_referee']?.toString() ?? '';
                  actaScorekeeper = details['scorekeeper']?.toString() ?? '';
                  actaMatchDate = DateTime.tryParse(details['match_date']?.toString() ?? '');
                  actaTournamentId = details['tournament_id']?.toString();
                  actaTeamAId = int.tryParse(details['team_a_id']?.toString() ?? '0') ?? 0;
                  actaTeamBId = int.tryParse(details['team_b_id']?.toString() ?? '0') ?? 0;
                  actaVenueId = details['venue_id']?.toString();
                } catch (e) {
                  if (context.mounted) {
                    context.showError(ConnectivityHelper.friendlyMessage(e, fallback: "No se pudo obtener el acta: $e"));
                  }
                  return;
                }
              }

              // 2. Logos y categoría desde tournaments.
              final tournamentData = await (db.select(db.tournaments)
                    ..where((t) => t.id.equals(actaTournamentId ?? ''))).getSingleOrNull();

              // 3. Rosters para restoreFromDatabase.
              final allDbPlayers = await db.select(db.players).get();
              final rosterA = allDbPlayers
                  .where((p) => p.teamId.toString() == actaTeamAId.toString())
                  .map((p) => CatalogPlayer(id: int.tryParse(p.id) ?? -1, name: p.name, teamId: p.teamId, defaultNumber: p.defaultNumber))
                  .toList();
              final rosterB = allDbPlayers
                  .where((p) => p.teamId.toString() == actaTeamBId.toString())
                  .map((p) => CatalogPlayer(id: int.tryParse(p.id) ?? -1, name: p.name, teamId: p.teamId, defaultNumber: p.defaultNumber))
                  .toList();

              // 4. Roster del acta (capitanes y titulares).
              final dbRosters = await (db.select(db.matchRosters)
                    ..where((t) => t.matchId.equals(actaMatchId))).get();

              // --- PARTE 3: hidratar matchRosters desde la nube si no hay local ---
              // (partido jugado en OTRO dispositivo: capitanes/titulares no están locales).
              var rostersForActa = dbRosters;
              if (rostersForActa.isEmpty) {
                // Asegurar la fila matches (FK de matchRosters).
                await db.into(db.matches).insertOnConflictUpdate(
                  MatchesCompanion.insert(
                    id: drift.Value(actaMatchId),
                    teamAName: actaTeamAName,
                    teamBName: actaTeamBName,
                    status: const drift.Value('FINISHED'),
                    tournamentId: drift.Value(actaTournamentId),
                    venueId: drift.Value(actaVenueId),
                    teamAId: drift.Value(actaTeamAId),
                    teamBId: drift.Value(actaTeamBId),
                    mainReferee: drift.Value(actaMainReferee),
                    auxReferee: drift.Value(actaAuxReferee),
                    scorekeeper: drift.Value(actaScorekeeper),
                    matchDate: drift.Value(actaMatchDate),
                    isSynced: const drift.Value(true),
                  ),
                );
                try {
                  final apiR = ref.read(matchApiProvider);
                  final cloudRosters = _unwrapOrThrow(await apiR.getMatchRosters(actaMatchId));
                  for (final r in cloudRosters) {
                    await db.into(db.matchRosters).insertOnConflictUpdate(
                      MatchRostersCompanion.insert(
                        matchId: actaMatchId,
                        playerId: r['player_id'].toString(),
                        teamSide: r['team_side'].toString(),
                        jerseyNumber: int.tryParse(r['jersey_number']?.toString() ?? '0') ?? 0,
                        isCaptain: drift.Value((r['is_captain']?.toString() ?? '0') == '1'),
                        isStarter: drift.Value((r['is_starter']?.toString() ?? '0') == '1'),
                        attended: drift.Value((r['attended']?.toString() ?? '0') == '1'),
                      ),
                    );
                  }
                  // Recargar para capitanes/titulares ya hidratados.
                  rostersForActa = await (db.select(db.matchRosters)
                        ..where((t) => t.matchId.equals(actaMatchId))).get();
                } catch (e) {
                  if (context.mounted) context.showError(ConnectivityHelper.friendlyMessage(e, fallback: "No se pudo traer el roster: $e"));
                }
              }

              final capA = rostersForActa.where((r) => r.teamSide == 'A' && r.isCaptain).firstOrNull;
              final capB = rostersForActa.where((r) => r.teamSide == 'B' && r.isCaptain).firstOrNull;
              final teamA = await (db.select(db.teams)
                    ..where((t) => t.id.equals(actaTeamAId.toString()))).getSingleOrNull();
              final teamB = await (db.select(db.teams)
                    ..where((t) => t.id.equals(actaTeamBId.toString()))).getSingleOrNull();

              // Titulares reales desde matchRosters → X con círculo en el PDF.
              final startersAIds = rostersForActa
                  .where((r) => r.teamSide == 'A' && r.isStarter)
                  .map((r) => int.tryParse(r.playerId) ?? -1)
                  .where((id) => id > 0)
                  .toSet();
              final startersBIds = rostersForActa
                  .where((r) => r.teamSide == 'B' && r.isStarter)
                  .map((r) => int.tryParse(r.playerId) ?? -1)
                  .where((id) => id > 0)
                  .toSet();

              // 5. Firmas de árbitros.
              final refSignatures = await ref.read(officialRepositoryProvider).getRefereeSignatures(
                    mainRefereeName: actaMainReferee,
                    auxRefereeName: actaAuxReferee,
                  );

              // --- PARTE 2: hidratar eventos desde la nube si no hay locales ---
              // Solo aplica a partidos jugados en OTRO dispositivo (sin gameEvents local).
              final localEvents = await (db.select(db.gameEvents)
                    ..where((t) => t.matchId.equals(actaMatchId))).get();

              if (localEvents.isEmpty) {
                // 1. Asegurar la fila matches local: FK de gameEvents + metadata de restore.
                //    Se inserta como FINISHED para no alterar el estado del calendario.
                await db.into(db.matches).insertOnConflictUpdate(
                  MatchesCompanion.insert(
                    id: drift.Value(actaMatchId),
                    teamAName: actaTeamAName,
                    teamBName: actaTeamBName,
                    status: const drift.Value('FINISHED'),
                    tournamentId: drift.Value(actaTournamentId),
                    venueId: drift.Value(actaVenueId),
                    teamAId: drift.Value(actaTeamAId),
                    teamBId: drift.Value(actaTeamBId),
                    mainReferee: drift.Value(actaMainReferee),
                    auxReferee: drift.Value(actaAuxReferee),
                    scorekeeper: drift.Value(actaScorekeeper),
                    matchDate: drift.Value(actaMatchDate),
                    isSynced: const drift.Value(true),
                  ),
                );

                // 2. Traer eventos de la nube e insertarlos en gameEvents (restore los reproducirá).
                try {
                  final apiEvents = ref.read(matchApiProvider);
                  final cloudEvents = _unwrapOrThrow(await apiEvents.getMatchEvents(actaMatchId));
                  final base = DateTime.now();

                  for (var i = 0; i < cloudEvents.length; i++) {
                    final e = cloudEvents[i];
                    final rawType = e['event_type']?.toString() ?? '';
                    final pts = int.tryParse(e['points_scored']?.toString() ?? '0') ?? 0;
                    // Fallback para eventos viejos sin event_type: al menos la anotación.
                    final type = rawType.isNotEmpty ? rawType : (pts > 0 ? 'POINT_$pts' : 'OTROS');
                    final pidRaw = e['player_id']?.toString();
                    final pid = (pidRaw == null || pidRaw.isEmpty || pidRaw == '0') ? null : pidRaw;

                    await db.into(db.gameEvents).insert(
                      GameEventsCompanion.insert(
                        matchId: actaMatchId,
                        type: type,
                        period: int.tryParse(e['period']?.toString() ?? '1') ?? 1,
                        clockTime: e['clock_time']?.toString().isNotEmpty == true
                            ? e['clock_time'].toString()
                            : '00:00',
                        playerId: drift.Value(pid),
                        createdAt: drift.Value(base.add(Duration(milliseconds: i))), // preserva el orden
                        isSynced: const drift.Value(true),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) context.showError(ConnectivityHelper.friendlyMessage(e, fallback: "No se pudieron traer los eventos: $e"));
                  // Se continúa: el PDF saldría con marcador pero sin jugadas.
                }
              }

              // 6. Restaurar estado del partido en el controller (scoreLog, eventos).
              final controller = ref.read(matchGameProvider.notifier);
              await controller.restoreFromDatabase(
                  matchId: actaMatchId,
                  fixtureId: match.id,
                  rosterA: rosterA,
                  rosterB: rosterB,
                  startersA: startersAIds,
                  startersB: startersBIds,
                  tournamentId: int.tryParse(actaTournamentId ?? '0') ?? 0,
                  venueId: int.tryParse(actaVenueId ?? '0') ?? 0,
                  teamAId: actaTeamAId,
                  teamBId: actaTeamBId,
                  mainReferee: actaMainReferee,
                  auxReferee: actaAuxReferee,
                  scorekeeper: actaScorekeeper,
                  markFinished: true,
                );

              // 7. OutcomePdfParams con coaches + firmas.
              final pdfParams = OutcomePdfParams(
                teamAName: actaTeamAName,
                teamBName: actaTeamBName,
                tournamentName: tournamentData?.name ?? '',
                categoryName: tournamentData?.category ?? '',
                tournamentLogoUrl: tournamentData?.logoUrl ?? '',
                refereeLogoUrl: tournamentData?.refereeLogoUrl ?? '',
                venueName: match.venueName ?? '',
                mainReferee: actaMainReferee,
                auxReferee: actaAuxReferee,
                scorekeeper: actaScorekeeper,
                coachA: teamA?.coachName ?? '',
                coachB: teamB?.coachName ?? '',
                captainAId: capA != null ? int.tryParse(capA.playerId) : null,
                captainBId: capB != null ? int.tryParse(capB.playerId) : null,
                matchDate: actaMatchDate,
                mainRefSignature: refSignatures.main,
                auxRefSignature: refSignatures.aux,
                tournamentId: actaTournamentId,
              );

              // 8. Navegar.
              if (!context.mounted) return;
              unawaited(Navigator.push(context, MaterialPageRoute(
                builder: (_) => ChangeOutcomeScreen(
                  matchId: actaMatchId,
                  teamAName: actaTeamAName,
                  teamBName: actaTeamBName,
                  pdfParams: pdfParams,
                ),
              )));
            },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fixtureAsync = ref.watch(localFixtureProvider(widget.tournamentId));

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: Colors.transparent, 
      
      appBar: AppBar(
        title: const Text("Calendario de Juegos", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.0)),
        backgroundColor: Colors.black.withValues(alpha: 0.6), 
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGenerationOptions(context),
        icon: const Icon(Icons.add_chart),
        label: const Text("Crear Calendario", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.black,
        elevation: 4,
      ),

      body: AppBackground(
        opacity: 0.8,
        child: fixtureAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
          error: (err, stack) => Center(child: Text("Error: $err", style: const TextStyle(color: Colors.redAccent))),
          data: (groupedRounds) {
            if (groupedRounds.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                      child: const Icon(Icons.calendar_month_outlined, size: 70, color: Colors.white54),
                    ),
                    const SizedBox(height: 24),
                    const Text("Aún no hay partidos", style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(
                      "Configura y genera el calendario\ndesde el botón inferior.", 
                      textAlign: TextAlign.center, 
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16)
                    ),
                  ],
                ),
              );
            }

            // --- LÓGICA DE CONTEO DE ENFRENTAMIENTOS ---
            List<Fixture> allMatches = [];
            for (var list in groupedRounds.values) {
              allMatches.addAll(list);
            }
            
            // Ordenar los partidos de forma cronológica (por Jornada)
            allMatches.sort((a, b) {
              int roundA = int.tryParse(a.roundName.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              int roundB = int.tryParse(b.roundName.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              if (roundA != roundB) return roundA.compareTo(roundB);
              return a.id.compareTo(b.id);
            });

            // Mapa para almacenar qué enfrentamiento es para cada partido
            Map<String, int> encounterMap = {};
            Map<String, int> pairCounts = {};

            for (var m in allMatches) {
              // Creamos una clave única para cada par de equipos (ej: "12_15")
              List<String> teams = [m.teamAId, m.teamBId];
              teams.sort();
              String pairKey = teams.join('_');
              
              pairCounts[pairKey] = (pairCounts[pairKey] ?? 0) + 1;
              encounterMap[m.id] = pairCounts[pairKey]!;
            }

            // 1. Configuramos la lista completa de opciones del Bottom Sheet
            List<String> allRounds = ["Todas", ...groupedRounds.keys];

            // 2. Establecemos la ÚLTIMA jornada como predeterminada si no hay selección
            String activeRound = "Todas";
            if (_selectedRound != null) {
              activeRound = _selectedRound!;
            } else if (groupedRounds.keys.isNotEmpty) {
              // Extraemos las llaves (nombres de jornada) y las ordenamos numéricamente
              List<String> sortedRoundKeys = groupedRounds.keys.toList();
              sortedRoundKeys.sort((a, b) {
                int roundA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                int roundB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                return roundA.compareTo(roundB);
              });
              // Tomamos la última de la lista ordenada
              activeRound = sortedRoundKeys.last;
            }

            // 3. Filtramos los datos
            Map<String, List<Fixture>> filteredRounds = {};
            if (activeRound == "Todas") {
              filteredRounds = groupedRounds;
            } else if (groupedRounds.containsKey(activeRound)) {
              filteredRounds[activeRound] = groupedRounds[activeRound]!;
            }

            return SafeArea(
              child: Column(
                children: [
                  
                  // --- BOTÓN DE FILTRO POR JORNADA (ABRE BOTTOM SHEET) ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Filtrar Partidos", 
                          style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showRoundsFilterBottomSheet(allRounds, activeRound),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3), 
                                borderRadius: BorderRadius.circular(16), 
                                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5), width: 1.5), 
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orangeAccent.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    activeRound.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.orangeAccent, 
                                      fontSize: 15, 
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.filter_list, color: Colors.orangeAccent, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- LISTA DE PARTIDOS FILTRADOS ---
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 100), 
                      itemCount: filteredRounds.keys.length,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final roundName = filteredRounds.keys.elementAt(index);
                        final matches = filteredRounds[roundName]!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Solo mostramos el separador si estamos en la vista "Todas"
                            if (activeRound == "Todas") 
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.orangeAccent,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.flag, color: Colors.black87, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            roundName.toUpperCase(), 
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black87, letterSpacing: 1.2)
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Expanded(child: Divider(color: Colors.white38, indent: 12)),
                                  ],
                                ),
                              ),
                            
                            // Renderizamos el Card enviando el número de enfrentamiento calculado
                            ...matches.map((m) => _buildMatchCard(context, m, encounterMap[m.id] ?? 1)),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // --- WIDGET HELPER PARA LOGOS ---
  Widget _buildTeamLogo(String? logoPath, String teamName) {
    final String initial = teamName.isNotEmpty ? teamName[0].toUpperCase() : '?';

    return Container(
      width: 55,
      height: 55,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 1.5),
      ),
      child: ClipOval(
        child: AppNetworkImage(
          rawPath: logoPath,
          displayWidth: 55,
          fallbackBuilder: (context) => Center(
            child: Text(initial, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white70)),
          ),
        ),
      ),
    );
  }

  // --- DISEÑO DE TARJETA DE PARTIDO PROFESIONAL ---
 Widget _buildMatchCard(BuildContext context, Fixture match, int encounterNumber) {
  final isPlayable = match.status == 'SCHEDULED' || 
                     match.status == 'PENDING' || 
                     match.status == 'IN_PROGRESS' || 
                     match.status == 'PLAYING';

  final isFinished = match.status == 'FINISHED';

  String dateFormatted = "Horario por definir";
  if (match.scheduledDatetime != null) {
    final dt = match.scheduledDatetime!;
    dateFormatted = "${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}  •  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')} hrs";
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), 
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isFinished
                ? () => _showFinishedMatchOptions(context, match)
                : isPlayable ? () async {
              final dbBase = ref.read(databaseProvider);
              final currentState = ref.read(matchGameProvider);
              final String idABuscar = match.matchId ?? match.id;

              // --- 1. VALIDACIÓN DE PARTIDO ACTIVO ÚNICO ---
              if (currentState.matchId.isNotEmpty && currentState.matchId != idABuscar) {
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1F2B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    title: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                        SizedBox(width: 10),
                        Text("Partido en curso", style: TextStyle(color: Colors.white)),
                      ],
                    ),
                    content: const Text(
                      "Ya existe un partido activo en la mesa de control. Si continúas, se cerrará el actual para abrir el seleccionado. ¿Estás seguro?",
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.orangeAccent),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("SÍ, CONTINUAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
                // Se abandona el partido en memoria: limpiar también el
                // marcador difundido para no dejarlo colgado en la TV.
                ref.read(scoreboardMetaProvider.notifier).state = null;
                ref.invalidate(matchGameProvider); // Limpiamos la RAM
              }

              // --- 2. BUSCAR EN BD PARA REANUDAR ---
              final localMatch = await (dbBase.select(dbBase.matches)
                    ..where((t) => t.id.equals(idABuscar))).getSingleOrNull();

              if (localMatch != null && (localMatch.status == 'IN_PROGRESS' || localMatch.status == 'PLAYING')) {
                
                // --- NUEVO: RECUPERAR LOGOS DESDE LA TABLA TOURNAMENTS ---
                final tournamentData = await (dbBase.select(dbBase.tournaments)
                      ..where((t) => t.id.equals(localMatch.tournamentId ?? ''))).getSingleOrNull();

                final allDbPlayers = await dbBase.select(dbBase.players).get();
                final rosterA = allDbPlayers.where((p) => p.teamId.toString() == match.teamAId)
                    .map((p) => CatalogPlayer(id: int.tryParse(p.id) ?? -1, name: p.name, teamId: p.teamId, defaultNumber: p.defaultNumber)).toList();
                final rosterB = allDbPlayers.where((p) => p.teamId.toString() == match.teamBId)
                    .map((p) => CatalogPlayer(id: int.tryParse(p.id) ?? -1, name: p.name, teamId: p.teamId, defaultNumber: p.defaultNumber)).toList();

                final dbRosters = await (dbBase.select(dbBase.matchRosters)..where((t) => t.matchId.equals(localMatch.id))).get();
                final capA = dbRosters.where((r) => r.teamSide == 'A' && r.isCaptain).firstOrNull;
                final capB = dbRosters.where((r) => r.teamSide == 'B' && r.isCaptain).firstOrNull;

                if (context.mounted) {
                  unawaited(Navigator.push(context, MaterialPageRoute(builder: (_) => MatchControlScreen(
                    matchId: localMatch.id,
                    fixtureId: match.id,
                    teamAName: localMatch.teamAName,
                    teamBName: localMatch.teamBName,
                    mainReferee: localMatch.mainReferee ?? '',
                    auxReferee: localMatch.auxReferee ?? '',
                    scorekeeper: localMatch.scorekeeper ?? '',
                    tournamentName: tournamentData?.name ?? "Torneo Activo",
                    categoryName: tournamentData?.category ?? "LIBRE",
                    // LOGOS RECUPERADOS EXITOSAMENTE
                    tournamentLogoUrl: tournamentData?.logoUrl ?? "", 
                    refereeLogoUrl: tournamentData?.refereeLogoUrl ?? "",
                    venueName: match.venueName ?? '',
                    fullRosterA: rosterA,
                    fullRosterB: rosterB,
                    startersAIds: const {}, 
                    startersBIds: const {},
                    tournamentId: int.tryParse(localMatch.tournamentId ?? '0') ?? 0,
                    venueId: int.tryParse(localMatch.venueId ?? '0') ?? 0,
                    teamAId: localMatch.teamAId ?? 0,
                    teamBId: localMatch.teamBId ?? 0,
                    coachA: '', coachB: '',
                    captainAId: capA != null ? int.tryParse(capA.playerId) : null,
                    captainBId: capB != null ? int.tryParse(capB.playerId) : null,
                  ))));
                }
                return;
              }

              // --- 3. SI ES PARTIDO NUEVO, IR A SETUP ---
              if (context.mounted) {
                unawaited(Navigator.push(context, MaterialPageRoute(builder: (_) => MatchSetupScreen(
                  tournamentId: widget.tournamentId,
                  preSelectedFixture: match,
                ))));
              }
            } : () {
              context.showInfo("Partido en estado: ${match.status}");
            },
            splashColor: Colors.orange.withOpacity(0.3),
            highlightColor: Colors.orange.withValues(alpha: 0.1),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.03)],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatusBadge(match.status),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_month, size: 14, color: Colors.orangeAccent),
                                  const SizedBox(width: 5),
                                  Flexible(child: Text(dateFormatted, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on, size: 13, color: Colors.white54),
                                  const SizedBox(width: 5),
                                  Flexible(child: Text(match.venueName ?? 'Sede TBD', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(flex: 3, child: Column(children: [_buildTeamLogo(match.logoA, match.teamAName), const SizedBox(height: 8), Text(match.teamAName, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white), overflow: TextOverflow.ellipsis)])),
                        Expanded(
                          flex: 4, 
                          child: Column(
                            children: [
                              Text(isFinished && match.scoreA != null ? "${match.scoreA} - ${match.scoreB}" : "VS", style: const TextStyle(color: Colors.orangeAccent, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
                              const SizedBox(height: 4),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)), child: Text(_getEncounterText(encounterNumber).toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold))),
                              const SizedBox(height: 12),
                              Container(
                                width: 45, height: 45, 
                                decoration: BoxDecoration(color: isPlayable ? Colors.orangeAccent : Colors.white10, shape: BoxShape.circle), 
                                child: Icon((match.status == 'IN_PROGRESS' || match.status == 'PLAYING') ? Icons.restore : Icons.play_arrow_rounded, color: Colors.black, size: 26)
                              ),
                            ],
                          ),
                        ),
                        Expanded(flex: 3, child: Column(children: [_buildTeamLogo(match.logoB, match.teamBName), const SizedBox(height: 8), Text(match.teamBName, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white), overflow: TextOverflow.ellipsis)])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color txtColor;
    String label;

    switch (status) {
      case 'FINISHED':
        bgColor = Colors.green.withValues(alpha: 0.2);
        txtColor = Colors.greenAccent;
        label = "FINALIZADO";
        break;
      case 'IN_PROGRESS':
      case 'PLAYING':
        bgColor = Colors.orange.withValues(alpha: 0.2);
        txtColor = Colors.orangeAccent;
        label = "EN JUEGO";
        break;
      case 'FORFEIT_A':
      case 'FORFEIT_B':
        bgColor = Colors.red.withValues(alpha: 0.2);
        txtColor = Colors.redAccent;
        label = "AUSENCIA";
        break;
      case 'SCHEDULED':
      case 'PENDING':
      default:
        bgColor = Colors.white.withValues(alpha: 0.1);
        txtColor = Colors.white70;
        label = "PROGRAMADO";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: txtColor.withValues(alpha: 0.5))
      ),
      child: Text(label, style: TextStyle(color: txtColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
    );
  }
}

class LinearBinding {
   static LinearGradient linear(Color c1, Color c2) {
      return LinearGradient(
         begin: Alignment.topLeft,
         end: Alignment.bottomRight,
         colors: [c1, c2],
      );
   }
}