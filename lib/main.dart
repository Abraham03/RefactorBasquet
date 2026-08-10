import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/app/app.dart';
import 'package:myapp/app/app_bootstrap.dart';
import 'package:myapp/features/scoreboard/presentation/screens/secondary_display_app.dart';

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
