import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/features/scoreboard/data/external_display_service.dart';
import 'package:myapp/app/app_bootstrap.dart';
import 'package:myapp/features/scoreboard/presentation/screens/secondary_display_app.dart';

import 'package:myapp/features/home/presentation/screens/home_menu_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AppBootstrap(child: MyApp())));
}

/// Punto de entrada del isolate de la pantalla externa (HDMI / AnyCast).
///
/// Debe quedarse en `main.dart`: el plugin nativo lo invoca con
/// `DartExecutor.DartEntrypoint(path, "secondaryDisplayMain")` sin URI de
/// librería, así que el motor lo busca en la librería raíz. Moverlo a otro
/// archivo (o solo reexportarlo) rompe la resolución y la TV se queda negra.
/// El `@pragma` evita que el tree-shaking de release lo elimine.
@pragma('vm:entry-point')
void secondaryDisplayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SecondaryDisplayApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // El servicio queda vigilando el DisplayManager: cubre tanto el HDMI ya
    // puesto al abrir la app como el dongle AnyCast que enlaza 20 s después.
    ExternalDisplayService.instance.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      ExternalDisplayService.instance.requestShow();
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
