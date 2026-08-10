// Smoke test de la raíz de la app.
//
// Antes de la Fase 2 esto era IMPOSIBLE: `MyApp.initState` llamaba a
// `ExternalDisplayService.instance.start()`, que habla con el canal nativo y
// revienta con `MissingPluginException` en el host de tests. Por eso el
// `widget_test.dart` de la plantilla se borró en la Fase 0 en vez de arreglarse.
//
// Se inyecta `home:` para NO montar `HomeMenuScreen`: esa pantalla abre
// `StreamProvider` sobre drift y, bajo `flutter_test`, su desmontaje deja
// pendiente el timer de `StreamQueryStore.markAsClosed` (el binding falla con
// "A Timer is still pending"). Cubrir esa pantalla es trabajo de la Fase 5,
// cuando su lógica salga del widget; aquí se prueba el cableado de la raíz.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/app/app.dart';
import 'package:myapp/features/scoreboard/data/external_display_service.dart';
import 'package:myapp/features/scoreboard/presentation/providers/scoreboard_providers.dart';

/// Doble que no toca el canal nativo.
///
/// `noSuchMethod` cubre el resto de la superficie: solo interesa observar
/// `requestShow`, que es lo que dispara el ciclo de vida.
class _FakeExternalDisplayService implements ExternalDisplayService {
  int showRequests = 0;

  @override
  Future<void> requestShow({bool force = false}) async => showRequests++;

  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() {
  Future<void> pumpApp(WidgetTester tester, ExternalDisplayService display) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [externalDisplayProvider.overrideWithValue(display)],
        child: const MyApp(home: Scaffold(body: Text('home'))),
      ),
    );
  }

  testWidgets('MyApp monta y configura el MaterialApp', (tester) async {
    await pumpApp(tester, _FakeExternalDisplayService());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('home'), findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Van Ball');
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.theme?.useMaterial3, isTrue);
  });

  testWidgets('al volver de segundo plano se pide la pantalla externa', (
    tester,
  ) async {
    final display = _FakeExternalDisplayService();
    await pumpApp(tester, display);

    // Un `resume` sin `pause` previo no debe disparar nada.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(display.showRequests, 0);

    // pause -> resume sí: es el caso del AnyCast que se pierde al minimizar.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(display.showRequests, 1);
  });

  testWidgets('MyApp ya no arranca el servicio de pantalla externa', (
    tester,
  ) async {
    // El arranque es responsabilidad exclusiva de AppBootstrap. Antes se hacía
    // también desde `MyApp.initState`, con dos `start()` compitiendo.
    final display = _FakeExternalDisplayService();
    await pumpApp(tester, display);

    expect(display.showRequests, 0);
  });
}
