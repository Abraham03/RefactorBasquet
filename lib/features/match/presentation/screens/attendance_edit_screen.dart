import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/database/daos/roster_with_name.dart';
import 'package:myapp/core/constants/app_colors.dart';
import 'package:myapp/core/di/providers.dart';
import 'package:myapp/shared/widgets/app_feedback.dart';
import 'package:myapp/features/match/domain/constants/match_constants.dart';

class AttendanceEditScreen extends ConsumerStatefulWidget {
  final String matchId;
  final String teamAName;
  final String teamBName;
  const AttendanceEditScreen({
    super.key,
    required this.matchId,
    required this.teamAName,
    required this.teamBName,
  });

  @override
  ConsumerState<AttendanceEditScreen> createState() =>
      _AttendanceEditScreenState();
}

class _AttendanceEditScreenState extends ConsumerState<AttendanceEditScreen> {
  late Future<List<RosterWithName>> _future;
  final Map<String, bool> _attendance =
      {}; // playerId -> attended (estado editable)
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RosterWithName>> _load() async {
    final roster = await ref
        .read(attendanceRepositoryProvider)
        .getRoster(widget.matchId);
    for (final r in roster) {
      _attendance[r.playerId] = r.attended;
    }
    return roster;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await ref
        .read(attendanceRepositoryProvider)
        .saveAttendance(widget.matchId, _attendance);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isOk) {
      context.showSuccess("Asistencia actualizada");
      Navigator.pop(context);
    } else {
      // Se guardó local aunque la nube falle (offline-first).
      context.showWarning("Guardado local. Se subirá al reconectar.");
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: Colors.white,
        title: const Text(
          "Corregir Asistencia",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: FutureBuilder<List<RosterWithName>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            );
          }
          final roster = snap.data!;
          final teamA = roster
              .where((r) => r.teamSide == TeamSide.home)
              .toList();
          final teamB = roster
              .where((r) => r.teamSide == TeamSide.away)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _teamSection(widget.teamAName, teamA, AppColors.primary),
              const SizedBox(height: 16),
              _teamSection(widget.teamBName, teamB, AppColors.secondary),
            ],
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Icon(Icons.save_alt),
          label: Text(
            _saving ? "Guardando..." : "Guardar cambios",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: _saving ? null : _save,
        ),
      ),
    );
  }

  Widget _teamSection(String name, List<RosterWithName> players, Color color) {
    if (players.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Text(
            name.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
          ),
          child: Column(
            children: players.map((p) {
              final checked = _attendance[p.playerId] ?? false;
              return CheckboxListTile(
                value: checked,
                activeColor: color,
                checkColor: Colors.black,
                title: Text(
                  p.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  "#${p.jerseyNumber}",
                  style: const TextStyle(color: Colors.white54),
                ),
                onChanged: (v) =>
                    setState(() => _attendance[p.playerId] = v ?? false),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
