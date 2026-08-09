import 'package:flutter/material.dart';
import 'package:myapp/features/scoreboard/data/scoreboard_endpoint.dart';
import 'package:myapp/features/scoreboard/presentation/widgets/scoreboard_feed_view.dart';

/// App que corre en la pantalla externa (HDMI / dongle AnyCast).
///
/// Ojo: esto vive en un **isolate distinto** al de la app principal. No
/// comparte `ProviderScope`, memoria ni singletons; el único canal entre ambos
/// es el WebSocket a loopback. Por eso recorre los puertos candidatos: no puede
/// saber en cuál acabó escuchando el servidor.
class SecondaryDisplayApp extends StatelessWidget {
  const SecondaryDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: ScoreboardFeedView(
          endpoints: ScoreboardEndpoint.loopbackCandidates(),
          // La TV de la cancha no debe mostrar avisos de red al público.
          showConnectionBanner: false,
        ),
      ),
    );
  }
}

// El punto de entrada `secondaryDisplayMain` vive en lib/main.dart: el plugin
// nativo lo resuelve en la librería raíz, así que no puede moverse aquí.
