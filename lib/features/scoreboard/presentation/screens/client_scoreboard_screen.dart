// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/features/scoreboard/data/lan_scoreboard_discovery.dart';
import 'package:myapp/features/scoreboard/data/scoreboard_endpoint.dart';
import 'package:myapp/ui/widgets/app_feedback.dart';

import 'package:myapp/ui/widgets/app_background.dart';
import 'package:myapp/features/scoreboard/presentation/widgets/scoreboard_feed_view.dart';

/// Marcador remoto para una tablet en la misma red que la mesa de control.
///
/// Ya no contiene cliente WebSocket ni parseo propios: solo resuelve a qué
/// endpoints conectarse y delega en [ScoreboardFeedView], compartido con la
/// pantalla externa.
class ClientScoreboardScreen extends ConsumerStatefulWidget {
  const ClientScoreboardScreen({super.key});

  @override
  ConsumerState<ClientScoreboardScreen> createState() =>
      _ClientScoreboardScreenState();
}

class _ClientScoreboardScreenState
    extends ConsumerState<ClientScoreboardScreen> {
  final TextEditingController _ipController = TextEditingController();

  List<Uri>? _endpoints;

  LanScoreboardDiscovery? _discovery;
  StreamSubscription<DiscoveredScoreboard>? _discoverySub;
  final List<DiscoveredScoreboard> _found = [];
  bool _isScanning = false;

  void _startScan() {
    _stopScan();
    setState(() {
      _isScanning = true;
      _found.clear();
    });

    final discovery = LanScoreboardDiscovery();
    _discovery = discovery;
    _discoverySub = discovery.scan().listen(
      (result) {
        if (!mounted) return;
        // Un mismo host puede responder en varios puertos candidatos.
        if (_found.any((f) => f.host == result.host)) return;
        setState(() => _found.add(result));
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isScanning = false);
        if (_found.isEmpty) {
          context.showInfo(
            "No se encontró ninguna mesa de control. Revisa que esté en la misma red Wi-Fi.",
          );
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  void _stopScan() {
    _discoverySub?.cancel();
    _discoverySub = null;
    _discovery?.cancel();
    _discovery = null;
    if (mounted && _isScanning) setState(() => _isScanning = false);
  }

  void _connectTo(DiscoveredScoreboard target) {
    _stopScan();
    setState(() => _endpoints = [target.uri]);
  }

  void _connect() {
    final raw = _ipController.text;
    final error = ScoreboardEndpoint.validationError(raw);
    if (error != null) {
      context.showError(error);
      return;
    }

    final endpoints = ScoreboardEndpoint.candidatesForInput(raw);
    if (endpoints.isEmpty) {
      context.showError("IP o formato inválido.");
      return;
    }

    setState(() => _endpoints = endpoints);
  }

  void _unlink() => setState(() => _endpoints = null);

  @override
  void dispose() {
    _discoverySub?.cancel();
    _discovery?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endpoints = _endpoints;
    if (endpoints == null) return _buildForm();

    return Scaffold(
      backgroundColor: Colors.black,
      body: ScoreboardFeedView(
        endpoints: endpoints,
        onDisconnectRequested: _unlink,
      ),
    );
  }

  Widget _buildDiscoverySection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orangeAccent,
              side: const BorderSide(color: Colors.orangeAccent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isScanning ? _stopScan : _startScan,
            icon: _isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.orangeAccent, strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(
              _isScanning ? "Buscando… (tocar para detener)" : "Buscar en la red",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (_found.isNotEmpty) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _found.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final item = _found[i];
                return Material(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    leading:
                        const Icon(Icons.sports_basketball, color: Colors.orangeAccent),
                    title: Text(
                      item.label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      "${item.host}:${item.port}",
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: () => _connectTo(item),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildForm() {
    return Scaffold(
      appBar: AppBar(
        title: const Text("CONECTAR PIZARRA GIGANTE"),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: AppBackground(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(32),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              constraints: const BoxConstraints(maxWidth: 450),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_remote,
                      size: 80, color: Colors.orangeAccent),
                  const SizedBox(height: 24),
                  const Text(
                    "CONFIGURACIÓN DE RED",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Busca la mesa de control en la red o escribe su IP",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildDiscoverySection(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text("o a mano",
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12)),
                      ),
                      const Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _ipController,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    // Teclado de texto con filtro, no `TextInputType.number`:
                    // la mayoría de teclados Android no ofrecen el "." ni el
                    // ":" en el numérico, así que la IP era literalmente
                    // imposible de escribir.
                    keyboardType: TextInputType.text,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.:]')),
                    ],
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      hintText: "192.168.1.5",
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () => _ipController.clear(),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.orangeAccent, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _connect,
                      child: const Text(
                        "ENLAZAR TABLERO",
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
