// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/scoreboard/scoreboard_providers.dart';
import 'package:myapp/core/service/external_display_service.dart';
import 'package:myapp/ui/widgets/app_background.dart';
import 'package:myapp/ui/widgets/app_feedback.dart';

/// Diagnóstico del marcador: qué IP dictar, en qué puerto está escuchando,
/// cuántas pantallas hay enganchadas y en qué estado está la TV externa.
///
/// Existe porque antes esta información solo aparecía dentro de un partido, y
/// cuando algo fallaba no había forma de saber si el problema era la red, el
/// dongle o la app.
class ScoreboardServerScreen extends ConsumerWidget {
  const ScoreboardServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ip = ref.watch(localIpProvider).valueOrNull;
    final status = ref.watch(publisherStatusProvider).valueOrNull ??
        ref.watch(scoreboardPublisherProvider).currentStatus;
    final displayStatus = ref.watch(externalDisplayStatusProvider).valueOrNull ??
        ref.watch(externalDisplayProvider).status;

    final address = ip == null
        ? null
        : status.port == null
            ? ip
            : '$ip:${status.port}';

    return Scaffold(
      appBar: AppBar(
        title: const Text("ESTADO DEL MARCADOR"),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Card(
              title: "Red local",
              children: [
                _Row(
                  label: "Dirección para la tablet",
                  value: address ?? "Sin Wi-Fi",
                  valueColor:
                      address == null ? Colors.redAccent : Colors.greenAccent,
                  onCopy: address == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: address));
                          context.showSuccess("Dirección copiada");
                        },
                ),
                _Row(
                  label: "Servidor",
                  value: status.isRunning
                      ? "Escuchando en el puerto ${status.port}"
                      : "Detenido",
                  valueColor: status.isRunning
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
                _Row(
                  label: "Pantallas conectadas",
                  value: "${status.clientCount}",
                  valueColor: status.clientCount > 0
                      ? Colors.greenAccent
                      : Colors.amberAccent,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Card(
              title: "Pantalla externa (HDMI / AnyCast)",
              children: [
                _Row(
                  label: "Estado",
                  value: _displayLabel(displayStatus),
                  valueColor: _displayColor(displayStatus),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.lightBlueAccent,
                          side: const BorderSide(color: Colors.lightBlueAccent),
                        ),
                        onPressed: () async {
                          await ref
                              .read(externalDisplayProvider)
                              .requestShow(force: true);
                          if (context.mounted) {
                            context.showInfo("Buscando pantalla externa…");
                          }
                        },
                        icon: const Icon(Icons.cast_connected, size: 18),
                        label: const Text("Reintentar"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueGrey,
                          side: const BorderSide(color: Colors.blueGrey),
                        ),
                        onPressed: () async {
                          await ref.read(externalDisplayProvider).disable();
                          if (context.mounted) {
                            context.showInfo("Pantalla externa desconectada.");
                          }
                        },
                        icon: const Icon(Icons.cast_outlined, size: 18),
                        label: const Text("Desconectar"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              "En la tablet, abre «Pantalla Tablero» y usa «Buscar en la red», "
              "o escribe la dirección de arriba. Ambos dispositivos deben estar "
              "en la misma red Wi-Fi.",
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  static String _displayLabel(ExternalDisplayStatus s) => switch (s) {
        ExternalDisplayStatus.idle => "Sin pantalla detectada",
        ExternalDisplayStatus.probing => "Conectando…",
        ExternalDisplayStatus.showing => "Marcador visible",
        ExternalDisplayStatus.lost => "Se perdió la señal, reintentando…",
        ExternalDisplayStatus.disabled => "Desactivada por el usuario",
      };

  static Color _displayColor(ExternalDisplayStatus s) => switch (s) {
        ExternalDisplayStatus.showing => Colors.greenAccent,
        ExternalDisplayStatus.probing => Colors.amberAccent,
        ExternalDisplayStatus.lost => Colors.orangeAccent,
        ExternalDisplayStatus.disabled => Colors.blueGrey,
        ExternalDisplayStatus.idle => Colors.white54,
      };
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.valueColor,
    this.onCopy,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (onCopy != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16, color: Colors.white38),
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}
