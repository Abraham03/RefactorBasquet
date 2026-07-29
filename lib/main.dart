import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/service/external_display_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ui/home_menu_screen.dart'; 
import 'logic/match_game_controller.dart';
import 'ui/widgets/tv_scoreboard_widget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

// ---> PUNTO DE ENTRADA PARA EL ANYCAST (HDMI) <---
@pragma('vm:entry-point')
void secondaryDisplayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AnycastDisplayScreen(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Al arrancar la app, intenta mostrar el scoreboard si ya hay pantalla
    // conectada (p.ej. el cliente reabrió la app con el HDMI puesto).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ExternalDisplayService.instance.showScoreboard();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cuando la app vuelve al frente (resumed), re-asegura el scoreboard:
    // pudo haberse conectado la pantalla mientras estaba en segundo plano.
    if (state == AppLifecycleState.resumed) {
      ExternalDisplayService.instance.showScoreboard();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Van Ball',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const HomeMenuScreen(),
    );
  }
}

// ---> PANTALLA INVISIBLE DEL MONITOR CON RECONEXIÓN AUTOMÁTICA <---
class AnycastDisplayScreen extends StatefulWidget {
  const AnycastDisplayScreen({super.key});

  @override
  State<AnycastDisplayScreen> createState() => _AnycastDisplayScreenState();
}

class _AnycastDisplayScreenState extends State<AnycastDisplayScreen> {
  WebSocketChannel? _channel;
  MatchState? _currentState;
  String _teamAName = "Equipo A";
  String _teamBName = "Equipo B";
  int _teamAFouls = 0;
  int _teamBFouls = 0;

  @override
  void initState() {
    super.initState();
    _connectToLocalhost();
  }

  // Se conecta a sí mismo y si se cae, vuelve a intentar
  void _connectToLocalhost() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:8080'));
      _channel!.stream.listen(
        (message) {
          if (mounted) {
            final Map<String, dynamic> data = jsonDecode(message);
            setState(() {
               if (data.containsKey("state")) {
                 _currentState = MatchState.fromJson(data["state"]);
                 _teamAName = data["teamAName"] ?? "Equipo A";
                 _teamBName = data["teamBName"] ?? "Equipo B";
                 _teamAFouls = data["teamAFouls"] ?? 0;
                 _teamBFouls = data["teamBFouls"] ?? 0;
               } else {
                 _currentState = MatchState.fromJson(data);
               }
            });
          }
        },
        onDone: () => _retryConnection(),
        onError: (e) => _retryConnection(),
      );
    } catch (e) {
      _retryConnection();
    }
  }

  // Función mágica que reconecta la pantalla cuando sales de un partido a otro
  void _retryConnection() {
    if (mounted) {
      Future.delayed(const Duration(seconds: 1), () {
        _connectToLocalhost();
      });
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentState == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: TvScoreboardWidget(
          state: _currentState!,
          teamAName: _teamAName,
          teamBName: _teamBName,
          teamAFouls: _teamAFouls,
          teamBFouls: _teamBFouls,
        ),
      ),
    );
  }
}