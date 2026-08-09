import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/scoreboard/scoreboard_providers.dart';

/// Instancia al arrancar los servicios que deben vivir tanto como la app.
///
/// Los `Provider` de Riverpod son perezosos: si nadie los lee no se construyen
/// nunca. Antes eso lo resolvía `MatchControlScreen` levantando el servidor en
/// su `initState`, con dos consecuencias malas: la IP no existía fuera del
/// partido, y el receptor de la pantalla externa arrancaba con la app contra un
/// servidor que aún no estaba, quedándose en un bucle de reconexión en vacío.
class AppBootstrap extends ConsumerWidget {
  const AppBootstrap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(scoreboardBroadcasterProvider);
    ref.watch(externalDisplayProvider);
    return child;
  }
}
