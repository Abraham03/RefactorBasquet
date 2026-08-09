import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import '../core/constants/app_colors.dart';
import '../core/di/dependency_injection.dart';
import '../domain/services/outcome_changer.dart';
import '../logic/match_game_controller.dart';
import 'widgets/app_feedback.dart';
import '../core/network/connectivity_helper.dart';
class ChangeOutcomeScreen extends ConsumerStatefulWidget {
  final String matchId;
  final String teamAName;
  final String teamBName;
  final OutcomePdfParams pdfParams;

  const ChangeOutcomeScreen({
    super.key,
    required this.matchId,
    required this.teamAName,
    required this.teamBName,
    required this.pdfParams,
  });

  @override
  ConsumerState<ChangeOutcomeScreen> createState() => _ChangeOutcomeScreenState();
}

class _ChangeOutcomeScreenState extends ConsumerState<ChangeOutcomeScreen> {
  String _selected = 'NONE'; // NONE, TEAM_A, TEAM_B, BOTH, PROTEST
  bool _saving = false;
  final _sigController = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  final _obsController = TextEditingController();

  @override
  void dispose() {
    _sigController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  bool get _needsSignature => _selected == 'PROTEST';

  Future<void> _confirmAndSave() async {
    // Confirmación extra: se está modificando un acta firmada.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Text("Confirmar cambio", style: TextStyle(color: Colors.white, fontSize: 17)),
        ]),
        content: const Text(
          "Estás modificando el resultado de un acta ya finalizada y firmada. "
          "Esta acción regenera el PDF oficial. ¿Deseas continuar?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orangeAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sí, cambiar", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save();
  }

  Future<void> _save() async {
    // Validación: protesta exige firma.
    Uint8List? signature;
    if (_needsSignature) {
      if (_sigController.isEmpty) {
        context.showWarning("La protesta requiere una firma.");
        return;
      }
      signature = await _sigController.toPngBytes();
    }

    setState(() => _saving = true);

    // Reabrir el partido en el controller para reconstruir su estado (eventos,
    // scoreLog) antes de aplicar el cambio. El provider ya expone el controller.
    final controller = ref.read(matchGameProvider.notifier);

    // El desenlace 'PROTEST' se trata como 'NONE' en marcador (conserva real)
    // pero adjunta firma; el backend guarda la firma.
    final outcomeForRule = _selected == 'PROTEST' ? 'NONE' : _selected;

    final changer = ref.read(outcomeChangerProvider);
    try {
      final result = await changer.change(
      controller: controller,
      newOutcome: outcomeForRule,
      signature: signature,
      observaciones: _obsController.text.trim().isEmpty ? null : _obsController.text.trim(),
      pdfParams: widget.pdfParams,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result.success) {
      context.showSuccess("Resultado actualizado");
      Navigator.pop(context, true);
    } else {
      
      final msg = result.message ?? "No se pudo actualizar el resultado.";
      context.showError(ConnectivityHelper.isNetworkError(Exception(msg))
          ? ConnectivityHelper.friendlyMessage(Exception(msg))
          : msg);
    }
    } catch (e) {
      // El cambio de desenlace es online-only: si no hay red (o falla el
      // PDF/marcador), liberamos la UI y avisamos en vez de colgarnos.
      if (!mounted) return;
      setState(() => _saving = false);
      context.showError(ConnectivityHelper.friendlyMessage(e, fallback: "No se pudo actualizar el resultado: $e"));
    }
    
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: Colors.white,
        title: const Text("Cambiar Resultado", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("${widget.teamAName}  vs  ${widget.teamBName}",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          const Text("Selecciona el nuevo desenlace:",
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),

          _option('NONE', "Resultado normal", "Marcador real del partido", Icons.sports_basketball),
          _option('TEAM_A', "Default de ${widget.teamAName}", "Pierde por inasistencia (0-20)", Icons.flag),
          _option('TEAM_B', "Default de ${widget.teamBName}", "Pierde por inasistencia (20-0)", Icons.flag),
          _option('BOTH', "Doble default", "Ambos no se presentaron (0-0)", Icons.flag_circle),
          _option('PROTEST', "Bajo protesta", "Conserva marcador y agrega firma", Icons.gavel),

          const SizedBox(height: 16),
          TextField(
            controller: _obsController,
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: "Observaciones (opcional)",
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),

          // Firma solo si es protesta.
          if (_needsSignature) ...[
            const SizedBox(height: 16),
            const Text("Firma de protesta:", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Signature(controller: _sigController, height: 160, backgroundColor: Colors.white),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _sigController.clear(),
                icon: const Icon(Icons.clear, color: Colors.redAccent, size: 18),
                label: const Text("Limpiar", style: TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ],
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
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.save_alt),
          label: Text(_saving ? "Guardando..." : "Aplicar cambio",
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onPressed: _saving ? null : _confirmAndSave,
        ),
      ),
    );
  }

  Widget _option(String value, String title, String subtitle, IconData icon) {
    final selected = _selected == value;
    return Card(
      color: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppColors.primary : Colors.transparent, width: 1.5),
      ),
      child: ListTile(
        leading: Icon(icon, color: selected ? AppColors.primary : Colors.white54),
        title: Text(title, style: TextStyle(color: Colors.white, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: selected ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
        onTap: () => setState(() => _selected = value),
      ),
    );
  }
}