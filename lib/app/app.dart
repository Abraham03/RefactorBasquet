import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/features/home/presentation/screens/home_menu_screen.dart';
import 'package:myapp/features/scoreboard/presentation/providers/scoreboard_providers.dart';
import 'package:myapp/app/theme/app_theme.dart';

/// Raíz de la app.
///
/// Extraída de `main.dart` para que ese archivo quede solo con los dos puntos
/// de entrada (`main` y `secondaryDisplayMain`) y para que esta clase se pueda
/// montar en un test de widget.
///
/// Es `ConsumerStatefulWidget` porque necesita el `ref` para pedirle a la
/// pantalla externa que vuelva tras un `resume`. Antes lo hacía contra el
/// singleton `ExternalDisplayService.instance`, lo que hacía imposible
/// sustituirlo en un test: `initState` llamaba al canal nativo y reventaba con
/// `MissingPluginException`.
class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key, this.home = const HomeMenuScreen()});

  /// Pantalla inicial. Inyectable para poder montar la raíz en un test sin
  /// arrastrar `HomeMenuScreen`, que abre streams de drift y tarda minutos en
  /// estabilizarse bajo `flutter_test`. En producción nunca se pasa.
  final Widget home;

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // El arranque del servicio vive en AppBootstrap: es el único punto que lo
    // levanta. Aquí solo se reacciona al ciclo de vida.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      ref.read(externalDisplayProvider).requestShow();
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
      theme: AppTheme.light,
      home: widget.home,
    );
  }
}
