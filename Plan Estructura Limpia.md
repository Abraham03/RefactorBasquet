# Plan de Estructura Limpia — myapp v2.1.5+2

Refactor por fases hacia arquitectura limpia **feature-first**. Cada fase = 1 rama + 1 commit, entra a `main` **solo en verde**. La Fase 1 es exclusivamente movimiento de archivos: cero cambios de lógica.

**Objetivos del proyecto que guían cada decisión:** publicar en Play Store · poder agregar/modificar features · poder dar mantenimiento.

---

## §0 — Diagnóstico

| Área | Problema | Evidencia |
|---|---|---|
| DI | `databaseProvider` y `apiServiceProvider` duplicados → **2 instancias distintas de `ApiService`** conviviendo | `core/di/dependency_injection.dart:15,26` vs `logic/tournament_provider.dart:6` y `logic/catalog_provider.dart:11` |
| DI | Providers declarados dentro de archivos de widget | `ui/team_detail_screen.dart:530`, `ui/fixture_list_screen.dart:26`, `ui/widgets/scoreboard_feed_view.dart:10` |
| Testabilidad | Singletons duros anulan los overrides de Riverpod | `core/database/app_database.dart:29-31` (`factory AppDatabase() => _instance`), `LocalWebSocketServer.instance`, `ExternalDisplayService.instance` (arrancado **2 veces**: `main.dart:43` + `core/scoreboard/scoreboard_providers.dart:62`) |
| Red | God class de 30 métodos con `http.post`/`http.get` **top-level** (no inyectables) → la capa de red no se puede testear. 30 literales `?action=`. 3 convenciones de error incompatibles: `Future<bool>` catch→false (~14 métodos, destruye la causa), `throw Exception('...: $e')` y `Future<ApiResult>` (solo 5) | `core/service/api_service.dart` |
| Red | `_checkResponse` existe pero ~20 métodos inlinean el mismo `if (statusCode == 200 \|\| 201)` | `core/service/api_service.dart:625` |
| Capas | `onTap` de ~250 líneas: llamada API + 6 queries drift + **2 upserts idénticos** a `matches` + inserts de roster/eventos + `restoreFromDatabase(14 args)` + navegación | `ui/fixture_list_screen.dart:375-637` |
| Capas | `_syncData()` de 270 líneas: borra 7 tablas y reinserta **sin transacción** (fallo a mitad ⇒ base parcialmente vacía) | `ui/home_menu_screen.dart:803-1071` |
| Capas | 7 pantallas importan `core/database/app_database.dart`; 7 usan `apiServiceProvider` directo | — |
| Dependencias | El contrato de red depende de la capa de presentación | `core/scoreboard/scoreboard_payload.dart:4` → `logic/match_game_controller.dart` |
| Dominio | **Cero interfaces de repositorio.** `MatchFinalizer` depende de `AppDatabase` + `ApiService` + `MatchGameController` concretos | `domain/services/match_finalizer.dart`, `core/di/dependency_injection.dart:44-50` |
| Serialización | `MatchState.toJson()` emite **14 de 30 campos** (pierde `matchId`, `playerStats`, `scoreLog`, rosters, `periodScores`, árbitros) — y ese subconjunto es a la vez el formato de cable y el de persistencia | `logic/match_game_controller.dart:247-263` |
| DRY | 5 bloques duplicados: subida offline de jugador ×3, mapper evento→payload byte-idéntico ×2, descarga de fixture ×3, "nube o local con id temporal" ×6 (con 3 estrategias de id distintas), firmas de árbitro ×2 + código muerto marcado `// ignore: unused_local_variable` | ver Fase 6 |
| God class | `MatchGameController`: 1.697 líneas / ~55 métodos, con `_timer`, `_isFinished` y `_history` **fuera** del state (el undo no es testeable). `matchGameProvider` es global, sin `.family` ni `autoDispose` | `logic/match_game_controller.dart:300-1697,1901` |
| God class | `pdf_generator.dart`: 1.537 líneas con ~140 `static const double` de coordenadas | `core/utils/pdf_generator.dart:13-141` |
| Calidad | `flutter_lints` con **todas** las reglas comentadas, sin `exclude` de `.g.dart`, sin `strict-casts`. `logStatements: true` en release. 5 pantallas con `ignore_for_file: use_build_context_synchronously` | `analysis_options.yaml`, `core/database/app_database.dart:64` |
| Tests | Solo `test/scoreboard/` (5 archivos). `test/widget_test.dart` es la plantilla del contador y **falla** (pumpea `MyApp()` sin `ProviderScope` y busca `find.text('0')`) | `test/` |

**Módulo de referencia — el patrón a replicar, no a inventar:** `lib/core/scoreboard/`. Uniones selladas (`ScoreboardFeedEvent`), interfaces `ScoreboardPublisher`/`ScoreboardSubscriber`, puertos centralizados en `scoreboard_endpoint.dart`, `tryDecode()` que nunca lanza, payload versionado con back-compat, DI en su propio archivo, y los únicos tests reales del repo.

Otros activos reutilizables ya existentes: `ApiResult`, `SyncResult`/`FinalizeResult`/`SavePlayerResult`, `AppFeedback` (centraliza ~50 snackbars), `ConnectivityHelper` (usado en solo 3 de ~20 archivos con I/O), `ImageUrlResolver`/`AppNetworkImage`, `head_to_head_counter.dart` (puro), y `match_control_screen.dart:1222-1288` (`_finishMatchProcess`, la delegación correcta a generalizar).

---

## §0-bis — Invariantes irrompibles

Aplican a **todas** las fases, sin excepción. Cada fase declara `Contrato externo: intacto` con su método de verificación.

### I1 — La app queda funcional y publicable al cerrar cada fase

Ninguna fase deja trabajo a medias ni depende de que la siguiente "la termine". Si una fase no cierra en verde se descarta la rama y `main` queda como estaba. **Corolario: se puede compilar y subir a Play Store en cualquier punto entre fases.**

### I2 — Cero cambios al contrato del backend PHP (`vanball.com.mx/api.php`)

Lo que viaja por la red es intocable: mismo host, mismo `?action=`, mismo método HTTP, mismas claves y mismos tipos en el body, mismo parsing de la respuesta. Solo cambia **cómo** se construye la petición del lado Dart, nunca **qué** se envía.

**Verificación (montada en Fase 0):** `ApiService` usa las funciones top-level `http.post`/`http.get`, que no admiten inyección — pero `package:http` 1.6 expone **`runWithClient`**, que instala un `Client` en la zona y es consultado tanto por las funciones top-level como por `BaseRequest.send()` (multipart). Eso permite capturar la petición real **sin tocar una línea de producción**.

Arnés: [`test/support/request_recorder.dart`](test/support/request_recorder.dart) · goldens: [`test/core/network/api_contract_golden_test.dart`](test/core/network/api_contract_golden_test.dart) · fixtures: `test/fixtures/requests/*.json` (34 fixtures que cubren las **30** acciones, incluidas las ramas de `createTeam` con/sin `tournament_id` y de multipart con/sin PDF).

> Si el golden cambia, la fase está mal. **Nunca se actualiza el fixture para que pase el test.**

- Fase 3: los `Future<bool>` que hoy tragan la causa pasan a `Result<T>` ⇒ cambia lo que ve el **llamador Dart**, no lo que ve el servidor.
- Fase 4: renombrar `Team`→`CatalogTeam` toca **nombres de clase Dart**, jamás claves JSON. Los `fromJson`/`toJson` siguen leyendo `'team_a'`, `'player_id'`, etc.
- Fase 6: deduplicar el mapper evento→payload es donde más fácil se rompe el contrato sin darse cuenta.

### I3 — Cero cambios al esquema de la base de datos

Sin tablas nuevas, sin columnas nuevas, sin renombrados, sin cambios de tipo, sin tocar `schemaVersion` de drift, sin migraciones. **La app instalada debe abrir su `.sqlite` existente sin migrar.**

**Verificación (montada en Fase 0):**

```bash
dart run drift_dev schema dump lib/core/database/app_database.dart schema/current.json
diff schema/base.json schema/current.json   # debe ser vacío
```

`schema/base.json` (54 KB, 10 tablas) está commiteado como referencia. Además [`test/core/database/schema_guard_test.dart`](test/core/database/schema_guard_test.dart) afirma en cada `flutter test` que `schemaVersion == 4` y que el archivo sigue llamándose `basketball_league.sqlite`.

- Mover `tables/app_tables.dart` obliga a regenerar `.g.dart`, pero el esquema resultante debe ser **idéntico**.
- `AppDatabase.forTesting(QueryExecutor)` (Fase 2) es un constructor adicional: no toca el esquema.
- Fase 5 envuelve el wipe+insert de 7 tablas en `db.transaction()`: cambia la **atomicidad**, no el esquema ni el resultado en el camino feliz.

### I4 — El protocolo del marcador (WS local) solo crece de forma aditiva

Un receptor con la build vieja debe seguir decodificando el payload de la build nueva. Se mantiene `schemaVersion: 1` y los campos nuevos son **opcionales**. `scoreboard_payload.dart` ya tiene back-compat con el formato plano legacy — se replica ese criterio.

**Verificación:** test que decodifica el payload nuevo usando el parser v1 capturado.

---

## §1 — Decisión de arquitectura: feature-first híbrido

**Elección: feature-first con capas internas.** Justificación contra los tres objetivos del proyecto:

- **Play Store** — fases pequeñas y reversibles ⇒ se puede publicar entre fases sin congelar el refactor. Layer-first obliga a tocar 4 carpetas por cambio, lo que hace que cada commit sea grande y difícil de revertir antes de un release.
- **Agregar/modificar features** — hoy un cambio de negocio ("agregar tipo de falta") toca `ui/`, `logic/`, `data/` y `core/`. Feature-first lo confina a una carpeta.
- **Mantenimiento** — las capas **dentro** de cada feature hacen que la regla de dependencia sea verificable por `grep`, no por disciplina.

Layer-first ya fracasó en este repo: `lib/ui/` es un volcado plano de 16 pantallas y `lib/logic/` mezcla un controller de 1.697 líneas con providers de 14. A 20k líneas la navegación por capa deja de escalar. Además `core/scoreboard/` **ya es** un slice de feature bien hecho: se generaliza lo que funciona.

### Reglas de dependencia (verificables por grep)

1. `features/X` **no** importa `features/Y/presentation` ni `features/Y/data`. Solo `features/Y/domain`.
2. `core/` y `shared/` **nunca** importan `features/`.
3. `domain/` no importa `package:flutter/`, `package:drift/` ni `package:http/`.
4. `presentation/` no importa `core/database/` ni `*_api.dart`.

---

## §2 — Árbol destino y mapeo archivo por archivo

```
lib/
├── main.dart                                   ← SE QUEDA (secondaryDisplayMain, @pragma vm:entry-point)
│
├── app/
│   ├── app.dart                                ← MyApp extraído de main.dart          [Fase 2]
│   ├── app_bootstrap.dart                      ← ui/app_bootstrap.dart
│   └── theme/app_theme.dart                    ← ThemeData inline de main.dart:67-89  [Fase 9]
│
├── core/
│   ├── constants/
│   │   ├── api_constants.dart                  ← core/constants/api_constants.dart
│   │   └── app_colors.dart                     ← core/constants/app_colors.dart
│   ├── errors/
│   │   ├── app_exception.dart                  (nuevo)                                [Fase 3]
│   │   └── failure.dart                        (nuevo)                                [Fase 3]
│   ├── network/
│   │   ├── result.dart                         ← core/network/api_result.dart         [renombrado Fase 3]
│   │   ├── api_client.dart                     (nuevo)                                [Fase 3]
│   │   ├── api_actions.dart                    (nuevo, los 24 literales action=)      [Fase 3]
│   │   ├── connectivity_helper.dart            ← core/network/connectivity_helper.dart
│   │   └── api_service.dart                    ← core/service/api_service.dart        [transitorio: se disuelve en Fase 3]
│   ├── database/
│   │   ├── app_database.dart (+ .g.dart)       ← core/database/app_database.dart
│   │   ├── tables/app_tables.dart              ← core/database/tables/app_tables.dart
│   │   ├── tables/base_table.dart              ← core/database/tables/base_table.dart
│   │   └── daos/matches_dao.dart (+ .g.dart)   ← core/database/daos/matches_dao.dart
│   ├── di/
│   │   └── providers.dart                      ← core/di/dependency_injection.dart    [renombrado]
│   └── utils/
│       ├── image_format.dart                   ← core/utils/image_format.dart
│       ├── image_url_resolver.dart             ← core/utils/image_url_resolver.dart
│       ├── json_parsing.dart                   (nuevo: parseId)                       [Fase 4]
│       └── id_generator.dart                   (nuevo: TempId)                        [Fase 6]
│
├── shared/
│   ├── widgets/
│   │   ├── app_background.dart                 ← ui/widgets/app_background.dart
│   │   ├── app_feedback.dart                   ← ui/widgets/app_feedback.dart
│   │   ├── app_network_image.dart              ← ui/widgets/app_network_image.dart
│   │   └── glass_dashboard_card.dart           ← ui/widgets/glass_dashboard_card.dart
│   └── services/
│       └── image_loader_service.dart           ← core/service/image_loader_service.dart
│
└── features/
    │
    ├── home/presentation/screens/
    │   └── home_menu_screen.dart               ← ui/home_menu_screen.dart
    │
    ├── catalog/
    │   ├── domain/entities/catalog_models.dart ← core/models/catalog_models.dart
    │   ├── domain/entities/sync_result.dart    ← data/models/sync_result.dart
    │   ├── data/repositories/sync_repository.dart          ← data/repositories/sync_repository.dart
    │   ├── data/repositories/catalog_download_repository.dart (nuevo)                 [Fase 5]
    │   └── presentation/providers/
    │       ├── catalog_providers.dart          ← logic/catalog_provider.dart
    │       └── tournament_providers.dart       ← logic/tournament_provider.dart
    │
    ├── teams/
    │   ├── data/repositories/player_repository.dart        ← data/repositories/player_repository.dart
    │   └── presentation/screens/
    │       ├── team_management_screen.dart     ← ui/team_management_screen.dart
    │       └── team_detail_screen.dart         ← ui/team_detail_screen.dart
    │
    ├── fixture/presentation/
    │   ├── screens/fixture_list_screen.dart    ← ui/fixture_list_screen.dart
    │   ├── screens/manual_fixture_builder_screen.dart      ← ui/manual_fixture_builder_screen.dart
    │   └── widgets/tournament_rules_dialog.dart            ← ui/widgets/tournament_rules_dialog.dart
    │
    ├── match/
    │   ├── domain/
    │   │   ├── constants/match_constants.dart  ← core/constants/match_constants.dart
    │   │   ├── entities/match_finalize_params.dart         ← data/models/match_finalize_params.dart
    │   │   ├── entities/referee_signatures.dart            ← data/models/referee_signatures.dart
    │   │   ├── entities/match_state.dart       (extraído del controller)              [Fase 7]
    │   │   ├── mappers/match_payload_mapper.dart (nuevo)                              [Fase 6]
    │   │   ├── usecases/open_match_usecase.dart (nuevo)                               [Fase 5]
    │   │   ├── engines/*.dart                  (7 engines)                            [Fase 8]
    │   │   └── services/
    │   │       ├── match_finalizer.dart        ← domain/services/match_finalizer.dart
    │   │       ├── outcome_changer.dart        ← domain/services/outcome_changer.dart
    │   │       └── head_to_head_counter.dart   ← logic/head_to_head_counter.dart
    │   ├── data/repositories/
    │   │   ├── attendance_repository.dart      ← data/repositories/attendance_repository.dart
    │   │   └── official_repository.dart        ← data/repositories/official_repository.dart
    │   └── presentation/
    │       ├── controllers/match_game_controller.dart      ← logic/match_game_controller.dart
    │       ├── providers/starters_providers.dart           ← logic/starters_persistence_provider.dart
    │       └── screens/
    │           ├── match_control_screen.dart               ← ui/match_control_screen.dart
    │           ├── match_setup_screen.dart                 ← ui/match_setup_screen.dart
    │           ├── starters_selection_screen.dart          ← ui/starters_selection_screen.dart
    │           ├── attendance_edit_screen.dart             ← ui/attendance_edit_screen.dart
    │           ├── change_outcome_screen.dart              ← ui/change_outcome_screen.dart
    │           └── protest_signature_screen.dart           ← ui/protest_signature_screen.dart
    │
    ├── scoreboard/
    │   ├── domain/
    │   │   ├── scoreboard_payload.dart         ← core/scoreboard/scoreboard_payload.dart
    │   │   └── scoreboard_transport.dart       ← core/scoreboard/scoreboard_transport.dart
    │   ├── data/
    │   │   ├── scoreboard_endpoint.dart        ← core/scoreboard/scoreboard_endpoint.dart
    │   │   ├── scoreboard_broadcaster.dart     ← core/scoreboard/scoreboard_broadcaster.dart
    │   │   ├── ws_scoreboard_subscriber.dart   ← core/scoreboard/ws_scoreboard_subscriber.dart
    │   │   ├── resilient_ws_client.dart        ← core/scoreboard/resilient_ws_client.dart
    │   │   ├── lan_scoreboard_discovery.dart   ← core/scoreboard/lan_scoreboard_discovery.dart
    │   │   ├── websocket_server.dart           ← core/network/websocket_server.dart
    │   │   └── external_display_service.dart   ← core/service/external_display_service.dart
    │   └── presentation/
    │       ├── providers/scoreboard_providers.dart         ← core/scoreboard/scoreboard_providers.dart
    │       ├── screens/client_scoreboard_screen.dart       ← ui/client_scoreboard_screen.dart
    │       ├── screens/scoreboard_server_screen.dart       ← ui/scoreboard_server_screen.dart
    │       ├── screens/secondary_display_app.dart          ← ui/secondary_display_app.dart
    │       └── widgets/
    │           ├── scoreboard_widget.dart      ← ui/widgets/scoreboard_widget.dart
    │           ├── tv_scoreboard_widget.dart   ← ui/widgets/tv_scoreboard_widget.dart
    │           └── scoreboard_feed_view.dart   ← ui/widgets/scoreboard_feed_view.dart
    │
    └── reports/
        ├── data/pdf_generator.dart             ← core/utils/pdf_generator.dart
        └── presentation/screens/pdf_preview_screen.dart    ← ui/pdf_preview_screen.dart
```

Se vacían y eliminan: `lib/ui/`, `lib/logic/`, `lib/data/`, `lib/domain/`, `lib/core/service/`, `lib/core/models/`, `lib/core/scoreboard/`.

### Decisiones no obvias (documentadas para no re-discutirlas)

- **`matches_dao.dart` se queda en `core/database/daos/`**, no en `features/match/data/`. Está declarado en `@DriftDatabase(daos: [...])` y su `.g.dart` está acoplado al de `AppDatabase`; moverlo a la feature obliga a un import invertido `core → features` (viola la regla 2). Regla: **el DAO es infraestructura; el repositorio de la feature lo consume.**
- **`api_service.dart` se mueve a `core/network/` en Fase 1 sin dividirse.** La Fase 1 no toma decisiones de diseño; la división por dominio ocurre en Fase 3, cuando ya hay tests y golden de peticiones.
- **`catalog_models.dart` va a `features/catalog/domain/entities/`** aunque lo consuman 4 features: catálogo es su dueño semántico y las demás importan solo `domain`, lo cual respeta la regla 1.
- **`core/scoreboard/` se mueve primero, como canario.** Es el único módulo con tests, así que valida el procedimiento de movimiento de inmediato.
- **`main.dart` no se mueve y `secondaryDisplayMain()` no se toca.** El plugin nativo lo invoca con `DartExecutor.DartEntrypoint(path, "secondaryDisplayMain")` **sin URI de librería**, así que el motor lo busca en la librería raíz. Moverlo —o incluso solo reexportarlo— rompe la resolución y la TV se queda negra.

---

## §3 — Fases

Formato de cada fase: **Objetivo · Archivos · Cambios · Principio + patrón · Tests · Contrato externo · Criterio de salida · Rollback**.

---

### Fase 0 — Red de seguridad y congelado de contratos

**Objetivo:** que exista un semáforo verde/rojo confiable, y un golden de backend y de esquema, **antes** de tocar un solo archivo.

**Archivos:** `analysis_options.yaml`, `pubspec.yaml`, `test/widget_test.dart` (borrar), `test/fixtures/requests/*` (nuevo), `schema/base.json` (nuevo), `test/features/match/match_constants_test.dart` (nuevo).

**Cambios:**

1. `analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
    - "build/**"
  errors:
    todo: ignore

linter:
  rules:
    - always_use_package_imports    # lista de trabajo de la Fase 1.A: 136 -> 0
    - unawaited_futures             # clase de bug real: 12 issues
    - avoid_print                   # 1 issue
    - depend_on_referenced_packages # en 0 hoy: candado
    - use_super_parameters          # en 0 hoy: candado
```

   **Criterio:** la Fase 0 debe dejar un semáforo **confiable**. Una regla que arranca en rojo con cientos de issues no es red de seguridad, es ruido que oculta las regresiones reales. Solo entran reglas que están en 0 hoy, o que son la lista de trabajo explícita de una fase.

   **Diferido a la Fase 9 (medido, no re-discutir sin volver a medir):**

   | Regla | Issues al activarla | Motivo |
   |---|---|---|
   | `strict-casts: true` | **119 ERRORES** (`argument_type_not_assignable` ×103, `invalid_assignment` ×14, …) | El `List<dynamic> fixturesRaw` de `catalog_models` se propaga por toda la app. Entra cuando la Fase 4 tipe los modelos |
   | `strict-raw-types`, `avoid_dynamic_calls` | mismo origen | idem |
   | `prefer_final_locals` | 155 info | Cosmético; arreglarlo en Fase 1 contaminaría el diff de "solo mover archivos" |
   | `directives_ordering` | 49 info | Se reordenan solos en la Fase 1.A |

2. `dev_dependencies` mínimas, sin codegen nuevo:

```yaml
  mocktail: ^1.0.4     # mocks sin build_runner (mockito exige codegen: descartado)
  fake_async: ^1.3.1   # necesario para testear el Timer de MatchGameController (Fase 8)
```

   `package:http/testing.dart` (`MockClient`) **ya viene con `http`**: no hace falta nada más para testear la capa de red. `integration_test` se difiere a Fase 10.

3. **Borrar** `test/widget_test.dart`. Prueba un contador que no existe y falla. No se "arregla" aquí porque `MyApp.initState` llama `ExternalDisplayService.instance.start()` → `MissingPluginException` en el test host. El smoke real de `MyApp` se escribe en **Fase 2**, cuando ese singleton ya es un provider sustituible.

4. **Congelar I2:** arnés `runWithClient` + 34 goldens que cubren las 30 acciones.

5. **Congelar I3:** dump de esquema a `schema/base.json` + `schema_guard_test.dart`.

6. Primer test propio: `match_constants_test.dart`, test de **caracterización** (congela lo que el código hace hoy, no lo que debería hacer) sobre `EventType`, `MatchStatus`, `TeamSide` y `ForfeitStatus`.

7. Registrar la **línea base** en §4.4.

**Principio/patrón:** ninguno de diseño — es infraestructura de verificación. Sin esto, todas las fases siguientes son cambios a ciegas.

**Contrato externo:** se **crea** el mecanismo que lo protege. Nada de código productivo cambia.

**Criterio de salida:** `flutter test` verde con tests propios nuevos; `flutter analyze` con 0 errores; `schema/base.json` y los fixtures commiteados; **el golden demostradamente detecta una ruptura de contrato**.

**Rollback:** `git revert`. Cero riesgo funcional (solo tooling y tests).

#### ✅ Resultado (2026-08-09)

| Métrica | Antes | Después |
|---|---|---|
| `flutter analyze` | 5 info, 0 errores | 153 info, **0 errores / 0 warnings** (136 son la lista de trabajo de Fase 1.A) |
| `flutter test` | 29 verdes, **1 rojo** | **83 verdes, 0 rojos** |
| `flutter build apk --release` | — | ✔ 69.2 MB |
| Goldens de contrato (I2) | 0 | 34 fixtures / 30 acciones |
| Guard de esquema (I3) | 0 | `schema/base.json` + 3 tests |

**Validación del mecanismo, no solo de los tests.** Un golden que nunca falla no protege nada. Se rompió el contrato a propósito (`"score_a"` → `"score_A"` en `updateMatchOutcome`), se confirmó que 2 goldens se pusieron en rojo señalando el offset exacto del carácter, y se revirtió. El arnés funciona.

**Hallazgos corregidos respecto al diagnóstico inicial:**
- Las acciones del backend son **30**, no 24.
- `strict-casts` no era viable en Fase 0: abre 119 errores (ver tabla de diferidos arriba).

---

### Fase 1 — Solo movimiento de archivos y creación de carpetas

**Objetivo:** el árbol destino completo, con **cero** cambios fuera de líneas `import`/`export`.

#### 1.A — Normalizar todos los imports a `package:myapp/` (commit propio, sin mover nada)

Estado actual: 56 imports `package:` vs **136 relativos**, mezclados en el mismo archivo (`dependency_injection.dart` tiene ambos estilos; `fixture_list_screen.dart` llega a tener `import '../ui/widgets/...'` desde dentro de `ui/`).

**Decisión: `package:myapp/` absoluto en todo el proyecto.** Razones concretas:

- Al mover un archivo, con imports absolutos solo cambia **la ruta citada**; con relativos hay que recalcular cada `../` **dentro** del archivo movido *y* en todos sus consumidores.
- Convierte la reescritura de imports de 1.B en un **reemplazo textual determinista**: por cada archivo movido, un solo find & replace global. Sin ambigüedad.
- Se hace cumplir automáticamente con el lint `always_use_package_imports` ya activado en Fase 0.

**Aplicación en masa:**
1. `dart fix --dry-run` → si reporta fixes para `always_use_package_imports`, aplicar con `dart fix --apply`.
2. Si no, el IDE ofrece *Convert to package import* en lote (*Source Action → Fix All in Workspace*) por directorio.
3. Fallback manual acotado: los 136 relativos en un pase; el analizador marca cualquier error al instante.

**Verificación 1.A:** `flutter analyze` verde y `git diff` muestra **solo** líneas `import`.

#### 1.B — Crear carpetas y mover con `git mv`, en orden de dependencia ascendente

Seis grupos; **`flutter analyze && flutter test` entre cada uno**.

| # | Grupo | Contenido | Nota |
|---|---|---|---|
| 1 | **Canario: scoreboard** | los 8 de `core/scoreboard/` + `core/network/websocket_server.dart` + `core/service/external_display_service.dart` + los 3 screens y 3 widgets | Único módulo con tests ⇒ valida el procedimiento de inmediato. Mover también `test/scoreboard/` → `test/features/scoreboard/` |
| 2 | **core estable** | `constants/*`, `network/{api_result,connectivity_helper}`, `utils/{image_format,image_url_resolver}`, `di/dependency_injection.dart`→`di/providers.dart`, `service/api_service.dart`→`network/api_service.dart` | `match_constants.dart` sale de `core/constants` hacia `features/match/domain/constants/` |
| 3 | **database** | `core/database/**` (ya está en su sitio) | **Gotcha:** cualquier movimiento aquí obliga a `dart run build_runner build --delete-conflicting-outputs` y a commitear el `.g.dart` regenerado. **Verificar I3 con el `diff` de esquema antes de continuar.** |
| 4 | **shared** | los 4 widgets genéricos → `shared/widgets/`; `image_loader_service.dart` → `shared/services/` | |
| 5 | **domain + data de features** | `core/models/catalog_models.dart`, `data/models/*`, `data/repositories/*`, `domain/services/*`, `logic/head_to_head_counter.dart` | Se vacían `lib/data/` y `lib/domain/` |
| 6 | **presentation** | los 16 screens de `ui/`, los 4 archivos restantes de `logic/`, `ui/app_bootstrap.dart`→`app/` | Se vacían `lib/ui/` y `lib/logic/` |

**Reescritura de imports tras cada `git mv`** — una sustitución por archivo movido, sobre `lib/` y `test/`, excluyendo `*.g.dart`:

```powershell
$old = 'package:myapp/ui/home_menu_screen\.dart'
$new = 'package:myapp/features/home/presentation/screens/home_menu_screen.dart'
Get-ChildItem -Path lib,test -Recurse -Filter *.dart |
  Where-Object { $_.Name -notlike '*.g.dart' } |
  ForEach-Object {
    $c = Get-Content $_.FullName -Raw
    if ($c -match $old) { ($c -replace $old, $new) | Set-Content $_.FullName -Encoding utf8 -NoNewline }
  }
```

**Restricciones duras de esta fase:**
- `main.dart` **no se mueve** y `secondaryDisplayMain()` **no se toca**.
- Extraer `MyApp` a `app/app.dart` es un cambio de lógica ⇒ **no** va aquí, va en Fase 2.
- No se renombra ninguna clase, no se borra ningún provider duplicado, no se toca una llave.

#### 1.C — Verificación

1. `flutter analyze` → mismo conteo que la línea base de Fase 0.
2. `flutter test` → los 5 tests de scoreboard + los de Fase 0, verdes.
3. **Prueba estructural del diff — la más importante:**
   ```bash
   git diff -M --numstat HEAD~1
   ```
   Todo archivo movido debe aparecer como *rename*. Para cada archivo con contenido modificado, `added == deleted`, y ambos números deben coincidir con el nº de líneas `import` afectadas. **Cualquier archivo donde `added != deleted` significa que se coló un cambio de lógica ⇒ revertir ese archivo.**
4. `git log --follow <archivo_movido>` conserva historia (garantizado por `git mv`).
5. `flutter build apk --release` compila ⇒ prueba que el tree-shaking sigue resolviendo `secondaryDisplayMain`.
6. `diff` del dump de esquema contra `schema/base.json` ⇒ vacío (I3).
7. **Smoke manual en dispositivo** (lo único que el análisis estático no cubre): abrir app → conectar HDMI/AnyCast → la TV pinta el marcador. Es el único riesgo real de esta fase.

**Contrato externo:** intacto por construcción — no se modifica una sola línea que no sea `import`.

**Criterio de salida:** `lib/ui/`, `lib/logic/`, `lib/data/`, `lib/domain/` no existen; 0 imports relativos; analyze y test en línea base; APK release compila; TV externa funciona.

**Rollback:** `git checkout main` y descartar la rama entera. Al ser solo renames, el revert es limpio.

#### ✅ Resultado (2026-08-09)

| Métrica | Antes | Después |
|---|---|---|
| `flutter analyze` | 153 info | **0 — "No issues found!"** |
| `flutter test` | 83 verdes | 83 verdes |
| `flutter build apk --release` | ✔ | ✔ 69.2 MB |
| Esquema drift (I3) | — | `diff` vacío |
| Goldens de contrato (I2) | 34 ✔ | 34 ✔ |
| Imports relativos | 136 | **0** | 0 |
| Renames detectados por git | — | **61** (historia preservada) |

**Commits** (uno por grupo, revertibles de forma independiente):

| Commit | Contenido |
|---|---|
| `Fase 1.0` | Los 17 issues que no eran de imports, **antes** de mover nada |
| `Fase 1.A` | 136 imports → `package:myapp/` vía `dart fix --apply` |
| `1.B grupo 1` | scoreboard (canario) — 26 archivos |
| `1.B grupo 2` | core estable — 23 archivos |
| `1.B grupo 4` | shared — 20 archivos |
| `1.B grupo 5` | domain + data → features — 24 archivos |
| `1.B grupo 6` | presentation → features — 30 archivos |

**Grupo 3 (database): sin movimientos.** Ya estaba en `lib/core/database/`, así que no hubo que regenerar `.g.dart` ni hubo riesgo para I3.

**Verificación estructural, grupo por grupo:** `git diff -M --numstat` dio `added == deleted` en **todos** los archivos de **todos** los grupos, y el filtro de líneas que no son `import` dio 0. `main.dart` cambió exclusivamente sus 4 imports; `secondaryDisplayMain` no se tocó.

**Lo que la Fase 1.0 tuvo que arreglar (aprendizaje aplicable a fases futuras):** dos tests leían **rutas de archivo literales** (`File('lib/core/service/api_service.dart')`), no imports, así que la reescritura automática no las tocaba y se rompieron al mover el archivo. Se corrigieron para localizar el archivo **escaneando `lib/`** en vez de por ruta fija; así el golden de cobertura sobrevivirá también a la división de `ApiService` en 5 datasources de la Fase 3.

#### Línea base de las reglas de dependencia

El movimiento **expone** las violaciones que ya existían; no las crea ni las corrige (Fase 1 no toca lógica). Números medidos al cerrar:

| Regla | Violaciones | Dónde | Fase que la cierra |
|---|---|---|---|
| **R1** `features/X` no importa `features/Y/{data,presentation}` | *(medir en F4)* | — | 4 |
| **R2** `core/`/`shared/` no importan `features/` | **3** | `core/di/providers.dart` (composition root: **excepción legítima**), `core/network/api_service.dart`, `core/database/daos/matches_dao.dart` | 3 y 4 |
| **R3** `domain/` no importa flutter/drift/http | **3** | `match/domain/services/match_finalizer.dart`, `scoreboard/domain/scoreboard_{payload,transport}.dart` | 7 y 8 |
| **R4** `presentation/` no importa `core/database` ni `api_service` | **10** | pantallas de fixture, home, match, teams | 5 |

---

### Fase 2 — Composition root único y muerte de los singletons

**Objetivo:** una sola instancia de cada dependencia, toda sustituible en tests.

**Archivos:** `core/di/providers.dart`, `core/database/app_database.dart`, `features/scoreboard/data/{websocket_server,external_display_service}.dart`, `features/scoreboard/presentation/providers/scoreboard_providers.dart`, `features/catalog/presentation/providers/*`, `main.dart`, `app/app.dart` (nuevo), `team_detail_screen.dart`, `fixture_list_screen.dart`, `scoreboard_feed_view.dart`.

**Cambios:**

1. Borrar `databaseProvider` de `tournament_providers.dart` y `apiServiceProvider` de `catalog_providers.dart`. **Fuente única: `core/di/providers.dart`.**
2. `AppDatabase`: eliminar `static final _instance` + `factory AppDatabase()`. Construcción en el provider con `ref.onDispose(db.close)`. Agregar `AppDatabase.forTesting(QueryExecutor e) : super(e)`. Cambiar `logStatements: true` → `logStatements: !kReleaseMode`.
3. `LocalWebSocketServer.instance` y `ExternalDisplayService.instance` → providers. **Un solo punto de arranque** de `ExternalDisplayService`: `AppBootstrap`; eliminar el arranque duplicado de `scoreboard_providers.dart:62`.
4. Los 3 providers declarados dentro de widgets se mueven al `presentation/providers/` de su feature.
5. Extraer `MyApp` de `main.dart` a `app/app.dart` ⇒ `main.dart` queda con `main()` + `secondaryDisplayMain()` únicamente.

**Principio/patrón:** **DIP** (todo se resuelve por el contenedor, nada por acceso estático) · **SRP** en `main.dart` · **Composition Root** (Riverpod como único grafo de objetos; el Singleton clásico se sustituye por lifetime gestionado por el contenedor).

**Tests:**
- `test/core/di/providers_test.dart`: `ProviderContainer` con `databaseProvider.overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory()))`; verificar por **identidad** que `syncRepositoryProvider` y `matchFinalizerProvider` reciben esa instancia.
- Override de `apiServiceProvider` con un fake mocktail ⇒ probar que llega a `PlayerRepository` y `AttendanceRepository`.
- `test/app/app_smoke_test.dart`: `pumpWidget(ProviderScope(overrides: [externalDisplayServiceProvider.overrideWithValue(FakeDisplayService())], child: MyApp()))` — ahora sí es posible.

> **Riesgo conocido (Windows):** `NativeDatabase.memory()` en `flutter test` corre en la VM y necesita `sqlite3.dll` accesible; `sqlite3_flutter_libs` solo cubre la app. Si falla: colocar `sqlite3.dll` en la raíz del proyecto (procedimiento documentado por drift) **o** testear repositorios contra la interfaz del DAO con fakes de mocktail. **Decidir en esta fase y anotarlo aquí.**

**Contrato externo:** intacto. `AppDatabase.forTesting` es aditivo; verificar `diff` de esquema (I3). Ninguna petición HTTP cambia (I2).

**Criterio de salida:** `grep -rn "final .*Provider" lib` solo devuelve resultados en `**/providers.dart` y `core/di/`; 0 ocurrencias de `.instance` en `lib/` salvo las documentadas; smoke test verde; app arranca en dispositivo y la TV sigue funcionando.

**Rollback:** revert del commit. Ningún cambio de esquema ni de datos.

#### ✅ Resultado (2026-08-09)

| Métrica | Antes | Después |
|---|---|---|
| `flutter analyze` | 0 | **0** |
| `flutter test` | 83 verdes | **93 verdes** |
| `flutter build apk --release` | ✔ | ✔ 69.2 MB |
| Esquema drift (I3) | — | `diff` vacío |
| Providers duplicados | 2 | **0** | 0 |
| Providers declarados en screens/widgets | 3 | **0** |
| Singletons estáticos (`.instance`) | 3 | **0** | 0 |
| Puntos de arranque de `ExternalDisplayService` | 2 | **1** (`AppBootstrap`) |

**El riesgo abierto de esta fase quedó descartado:** `NativeDatabase.memory()` **sí funciona** bajo `flutter test` en Windows sin necesidad de poner `sqlite3.dll` en la raíz. Se comprobó con una prueba desechable antes de escribir los tests reales, así que las fases siguientes pueden usar drift en memoria con confianza.

**Lo que ahora es posible y antes no:** `test/app/app_smoke_test.dart`. Con `ExternalDisplayService` como singleton estático, `MyApp.initState` llamaba al canal nativo y reventaba con `MissingPluginException`; por eso la Fase 0 **borró** el `widget_test.dart` de la plantilla en vez de arreglarlo. Ahora la raíz se monta con un doble del servicio.

**Dos decisiones tomadas durante la ejecución:**

1. **`MyApp` recibe `home` inyectable** (por defecto `HomeMenuScreen`, sin cambio en producción). Montar `HomeMenuScreen` en un test tarda minutos y falla con *"A Timer is still pending"*: sus `StreamProvider` sobre drift dejan pendiente el timer de `StreamQueryStore.markAsClosed` al desmontarse. Cubrir esa pantalla es trabajo de la **Fase 5**, cuando su lógica salga del widget.
2. **`matchGameProvider` se queda junto a su `StateNotifier`** en `match_game_controller.dart`. Colocar un `StateNotifierProvider` con su notifier es idiomático en Riverpod y ese archivo no es un widget. El criterio de salida es por tanto "ningún provider declarado en archivos de *pantalla o widget*", que sí se cumple.

**Reexports en lugar de tocar 6 pantallas:** al borrar los providers duplicados, `catalog_providers.dart` y `tournament_providers.dart` **reexportan** los del composition root (`export ... show apiServiceProvider`). Las pantallas que los importaban por esa ruta siguen compilando sin cambios, y el test verifica por identidad que ambas rutas resuelven al mismo provider.

**Guard de regresión:** `providers_test.dart` escanea `lib/` y falla si `databaseProvider` o `apiServiceProvider` vuelven a declararse en más de un archivo.

---

### Fase 3 — Capa de red: cliente inyectado, `Result` sellado y división por dominio

**Objetivo:** hacer `ApiService` testeable y romperla en 5 clases con una sola convención de errores, **sin cambiar una sola petición**.

**Sub-fases (commits independientes, cada uno verde):**

**3.1 — Infraestructura aditiva** (no rompe nada; nada la usa todavía)
- `core/errors/app_exception.dart`: jerarquía sellada `AppException` → `NetworkException` | `HttpStatusException` | `ApiBusinessException` | `ParseException` | `TimeoutException`.
- `core/network/result.dart`: `sealed class Result<T>` con `Ok<T>` / `Err<T>(AppFailure)`. **Dart 3 sealed + pattern matching ⇒ sin freezed.**
- `core/network/api_client.dart`: envuelve un `http.Client` **inyectado**; construye `Uri`, aplica timeout, verifica status (generaliza el `_checkResponse` de `api_service.dart:625`, hoy inlineado ~20 veces), decodifica, consulta `ConnectivityHelper` y devuelve `Result<T>`.
- `core/network/api_actions.dart`: los 30 literales en `abstract final class ApiActions`.
- `ApiResult` se conserva como **Adapter** deprecado sobre `Result` durante la migración.

**3.2 — Migración por dominio** (un commit por archivo)
`CatalogApi`, `TeamApi`, `FixtureApi`, `MatchApi`, `OfficialVenueApi` en `features/<f>/data/datasources/`. `ApiService` se mantiene como **Facade** delegando en las nuevas clases ⇒ los 7 screens y los repos siguen compilando sin tocarse (**Strangler Fig**).

**3.3 — Eliminación de la fachada**
Migrar los llamadores a los datasources y borrar `api_service.dart`. Desaparecen los `Future<bool>` que tragan la causa y los `.replaceFirst('Exception: ', '')` de la UI.

**Principio/patrón:** **SRP** (God class de 30 métodos → 5 clases cohesivas) · **DIP** (`http.Client` inyectado, no `http.post` global) · **OCP** (endpoint nuevo = método en su API, sin tocar código compartido) · **ISP** (cada feature depende solo de su datasource). Patrones: **Facade** (transición) · **Adapter** (`ApiResult`→`Result`) · **Strangler Fig** (migración) · **Result sellado** (reemplaza excepciones como control de flujo).

**Tests:** `MockClient` de `package:http/testing.dart`. Por cada datasource: 200 OK con JSON real capturado, 500, timeout, JSON malformado, y respuesta PHP `{"success": false, "message": ...}`. Test de arquitectura: ningún literal `action=` queda suelto en `lib/`.

**Contrato externo:** **es la fase de mayor riesgo para I2.** El `ApiClient` debe producir peticiones **byte-idénticas**. Los golden de `test/fixtures/requests/` se corren en **cada** commit de 3.1/3.2/3.3, no solo al cerrar la fase.

**Criterio de salida:** 0 ocurrencias de `http.get(`/`http.post(` top-level en `lib/`; todos los métodos de red devuelven `Result<T>`; 0 ocurrencias de `replaceFirst('Exception: '`; golden de peticiones sin diferencias; cobertura de la capa de red > 70 %.

**Rollback:** 3.1 es aditivo (revert trivial). 3.2/3.3 son revertibles **por dominio** gracias a la fachada.

#### ✅ Resultado de 3.1 y 3.2 (2026-08-09) · ⬜ 3.3 pendiente

| Métrica | Antes | Después |
|---|---|---|
| `flutter analyze` | 0 | **0** |
| `flutter test` | 93 verdes | **104 verdes** |
| `flutter build apk --release` | ✔ | ✔ 69.2 MB |
| Goldens de contrato (I2) | 35 ✔ | **35 ✔ sin tocar un fixture** |
| Esquema drift (I3) | — | `diff` vacío |
| `http.get`/`http.post` top-level | 30 | **0** | 0 |
| Copias del `if (statusCode == 200 \|\| 201)` | ~20 | **0** |
| Líneas de `ApiService` | 866 | **363** (pura delegación) | 0 |
| Clases con lógica de red | 1 God class | **5 datasources** |

**Lo importante:** se reescribieron las 30 acciones y **los 35 goldens siguen pasando sin modificar un solo fixture**. El contrato con el backend está intacto.

**Dos regresiones que el trabajo destapó y que se habrían colado sin los goldens:**

1. `create_team`, `add_player` y `create_tournament` leen `newId` **unas veces dentro de `data` y otras en la raíz del sobre**. El primer diseño de `ApiClient` solo entregaba `data`, así que hubo que añadir `postEnvelope` / `multipartEnvelope`. Sin eso, las altas que usan el segundo camino habrían empezado a fallar en producción.
2. `update_match_outcome` devuelve su mensaje en la raíz del sobre, y su PDF viaja **sin `contentType` explícito** (`application/octet-stream`), a diferencia de `sync_match` que sí lo declara `application/pdf`. El golden lo tenía congelado.

**Cambio de comportamiento deliberado:** antes **no había ningún timeout**. Una red que aceptaba la conexión pero no respondía dejaba la app colgada con el loader puesto indefinidamente. Ahora 30 s para JSON y 3 min para multipart (subir el PDF del acta por datos móviles legítimamente tarda).

**Deuda explícita y localizada:** la fachada conserva `_asBool`, `_asApiResult` y `_orThrow`, que **siguen destruyendo la causa del error** para no cambiar la firma pública. Están marcados como tales y desaparecen en 3.3.

#### ✅ Resultado de 3.3 (2026-08-09)

| Métrica | Antes | Después |
|---|---|---|
| `flutter analyze` | 0 | **0** |
| `flutter test` | 104 verdes | **105 verdes** |
| `flutter build apk --release` | ✔ | ✔ 69.2 MB |
| Goldens de contrato (I2) | 35 ✔ | **35 ✔, fixtures intactos desde la Fase 0** |
| Esquema drift (I3) | — | `diff` vacío |
| `ApiService` | 363 líneas | **borrada** |
| Violaciones R2 | 3 | **2** (`matches_dao` → Fase 4; el composition root es excepción legítima) |
| `replaceFirst('Exception: ')` en pantallas | 1 | **0** |

**Técnica que hizo el trabajo manejable:** marcar `apiServiceProvider` como `@Deprecated` **antes** de migrar. El analizador se convirtió en una checklist viva de los 22 puntos pendientes, que iba bajando con cada archivo.

**Dos mejoras que cayeron por el camino:**

1. `matches_dao.syncOfflinePlayersBeforeMatches` recibía **`dynamic api`**, lo que ocultaba el acoplamiento y desactivaba toda comprobación de tipos. Ahora recibe un **callback tipado**: el DAO declara *qué* necesita, no quién se lo da, y así `core/database` no tiene que importar `features/`.
2. `player_repository` registraba `"Creación online falló: $e"`; ahora registra el tipo y el mensaje de la `AppException`. Distinguir "sin internet" de "el backend rechazó el dorsal" cambia qué hacer.

**LA PRUEBA de I2:** los 34 fixtures de petición **siguen sin modificarse desde el commit de la Fase 0** (`f924171`), cuando se capturaron contra la vieja `ApiService`. Que sigan pasando contra una capa de red reescrita entera es la demostración de que el contrato con el backend está intacto.

---

### Fase 4 — Contratos de dominio: interfaces de repositorio y modelos tipados

**Objetivo:** que `domain` deje de depender de implementaciones concretas y desaparezcan los alias de import.

**Cambios:**

1. Interfaces abstractas en `features/<f>/domain/repositories/`: `ICatalogRepository`, `IPlayerRepository`, `IMatchRepository`, `IOfficialRepository`, `IFixtureRepository`. Las clases actuales de `data/` las implementan; **los providers exponen la interfaz, no la clase.**
2. Renombrar los modelos de catálogo para matar la colisión con drift: `Team`→`CatalogTeam`, `Player`→`CatalogPlayer`, `Tournament`→`CatalogTournament`, `Official`→`CatalogOfficial`. Elimina todos los `as catalog`/`as model` y el doble import del mismo archivo en `catalog_provider.dart:5-6`.
   > **I2:** esto toca **nombres de clase Dart**, jamás claves JSON. `fromJson`/`toJson` siguen leyendo `'team_a'`, `'player_id'`, etc.
3. `core/utils/json_parsing.dart` con `int parseId(Object? v)` ⇒ reemplaza las ~12 repeticiones de `int.parse(json['id'].toString())` (el backend PHP devuelve ints como string).
4. Agregar `toJson()`, `==` y `hashCode` a los 8 modelos. Los payloads salientes dejan de ser `Map` literales dentro de la capa de red.
   > **I2:** cada `toJson()` nuevo debe reproducir **exactamente** el `Map` literal que hoy construye `ApiService`, validado contra los fixtures de Fase 0.
5. Tipar `List<dynamic> fixturesRaw` y `finishedRosters` con modelos reales.

**Principio/patrón:** **DIP** (el dominio define el contrato, `data` lo cumple) · **LSP** (cualquier implementación —real, fake, offline— es sustituible) · **Repository** · **Value Object**.

**Tests:** round-trip `fromJson(toJson(x)) == x` por modelo; `parseId` con `int`, `String`, `null`, `"007"`; igualdad estructural; **golden de peticiones tras introducir cada `toJson()`**.

> **Nota deliberada:** **no** se introduce `freezed` ni `json_serializable` aquí. Son 8 modelos estables y el costo (2 generadores extra sobre un `build_runner` ya lento por los 10.864 líneas de `app_database.g.dart`, más la reescritura completa) no se paga. Queda como Fase 10 opcional.

**Contrato externo:** intacto. Riesgo alto en el punto 4 ⇒ golden obligatorio.

**Criterio de salida:** 0 imports con alias `as catalog`/`as model`; 0 `int.parse(...toString())`; `grep "import 'package:drift" lib/features/*/domain` vacío; golden de peticiones sin diferencias.

---

### Fase 5 — Sacar el negocio de las dos peores pantallas

**Objetivo:** eliminar los dos focos de riesgo más grandes. Va **después** de las fases 2–4 porque necesita DI limpia, `Result` y repositorios ya existentes.

**5.1 — `fixture_list_screen.dart:375-637`** (closure `onTap` de ~250 líneas)
→ `features/match/domain/usecases/open_match_usecase.dart`, que devuelve un `PreparedMatch` tipado. El widget queda con `await useCase(fixtureId)` + `switch` sobre `Result` + `AppFeedback` + `Navigator`. **De paso se elimina el upsert duplicado** (`:459-475` y `:533-549` son idénticos).
→ `restoreFromDatabase(14 args)` pasa a recibir un único `MatchRestoreSnapshot` (**Parameter Object**).

**5.2 — `home_menu_screen.dart:803-1071`** (`_syncData()`, 270 líneas: borra 7 tablas y reinserta)
→ `features/catalog/data/repositories/catalog_download_repository.dart` con `Future<Result<SyncResult>> downloadAll(tournamentId)`. Es la contraparte de descarga del `SyncRepository` de subida que ya existe.
→ **Corrección de bug de producción incluida:** envolver el wipe+insert de las 7 tablas en una única `db.transaction()`. Hoy no es atómico: un fallo a mitad deja la base parcialmente vacía.

**Principio/patrón:** **SRP** (el widget solo pinta y navega) · **Repository** · **Use Case / Command** · **Parameter Object** · **Unit of Work** (transacción drift).

**Tests:** repositorio con drift en memoria + `MockClient`; **test explícito de rollback** (forzar excepción a mitad de `downloadAll` y afirmar que las 7 tablas conservan su contenido previo); test de `OpenMatchUseCase` que verifica **un solo** upsert a `matches`.

**Contrato externo:** I2 intacto (mismas llamadas, reordenadas). I3 intacto: la transacción cambia la **atomicidad**, no el esquema.

**Criterio de salida:** `grep -rn "core/database" lib/features/*/presentation` → 0 (hoy 7); `grep -rn "apiServiceProvider" lib/features/*/presentation` → 0 (hoy 7); ningún método de widget supera 60 líneas.

#### ✅ Resultado (2026-08-10)

| Métrica | Antes | Después |
|---|---|---|
| `flutter analyze` | 0 | **0** |
| `flutter test` | 135 verdes | **152 verdes** |
| `flutter build apk --release` | ✔ | ✔ 69.2 MB |
| Goldens de contrato (I2) | 35 ✔ | 35 ✔ |
| Esquema drift (I3) | — | `diff` vacío |
| `fixture_list_screen.dart` | 1153 líneas | **918** |
| `home_menu_screen.dart` | 1442 líneas | **1323** |
| El `onTap` de "cambiar resultado" | 263 líneas | **4** |
| `_syncData()` | 272 líneas | **141** (100 de ellas, diálogos) |
| Parámetros de `restoreFromDatabase` | 13 sueltos | **1 snapshot** |
| Upserts duplicados a `matches` | 2 | **1** |

**CORRECCIÓN A ESTE PLAN.** El documento afirmaba que el wipe+insert de las 7 tablas "no es atómico" y que había que envolverlo en `db.transaction()`. **No era cierto:** la transacción ya estaba y cubría el borrado y las 8 inserciones. Se verificó antes de escribir nada; ese bug no existía y no se apunta como arreglado.

**Lo que sí apareció** al escribir el test de atomicidad: un fallo de esquema *dentro* de la transacción (p.ej. un nombre que excede el `CHECK` de longitud) subía como excepción suelta. La pantalla solo contempla `Ok`/`Err`, así que no se enteraba y el error llegaba al framework. Se añadió `StorageException` a la jerarquía sellada.

**Se resolvió el `TODO(fase-5)` de la Fase 4:** `fixturesRaw` y `finishedRosters` dejan de ser `List<dynamic>`. Ahora son `CatalogFixture` y `CatalogRoster`, parseados en el datasource. El `_toBool` privado del widget pasó a `parseBool` en `core/utils/`.

**17 tests nuevos.** Los que cubren decisiones que importan:
- los partidos `FINISHED` **sobreviven** a la descarga (la nube no los reenvía: borrarlos perdería rosters, asistencia y eventos sin vuelta atrás);
- **rollback real**: se fuerza un fallo a mitad y se comprueba que las tablas conservan su contenido previo;
- si falla el roster al abrir un partido ajeno, **sigue adelante sin capitanes** — el usuario puede corregir el resultado igual, abortar sería peor;
- un `player_id` `"0"` (falta de banca, tiempo muerto) se guarda como **nulo**: guardarlo tal cual violaría la FK contra `players`.

**R4 sigue en 12.** Bajar de ahí exige tocar las 10 pantallas restantes, no solo las dos peores. Queda para una fase posterior.

**Rollback:** 5.1 y 5.2 son commits separados e independientes.

---

### Fase 6 — Deduplicación (DRY)

**Objetivo:** una sola implementación de cada uno de los 5 bloques duplicados.

| Duplicado | Ubicaciones actuales | Destino |
|---|---|---|
| (a) Subida offline de jugador ×3 | `sync_repository.dart:262-301`, `starters_selection_screen.dart:113-147`, `match_game_controller.dart:1820-1889` | `PlayerRepository.savePlayer() → Result<SavePlayerResult>` |
| (b) Mapper evento→payload byte-idéntico ×2 (+ roster) | `sync_repository.dart:410-457` / `match_game_controller.dart:786-830`; roster `:473-490` / `:833-860` | `features/match/domain/mappers/match_payload_mapper.dart` (puro) |
| (c) Descarga + reinserción de fixture ×3 | `fixture_list_screen.dart:263-287`, `manual_fixture_builder_screen.dart:781-808`, `home_menu_screen.dart:912-932` | `FixtureRepository.refresh(tournamentId)` |
| (d) "Nube, si falla local con id temporal" ×6, con 3 estrategias de id distintas | `match_setup_screen.dart:756-781,856-890,1104-1135,1260-1300`, `team_management_screen.dart:245-300`, `player_repository.dart:103-132` | `OfflineFirstWriter<T>` (**Template Method**) + `core/utils/id_generator.dart` con una única `TempId` |
| (e) Firmas de árbitro ×2 + código muerto | `match_game_controller.dart:715-735` (con 2 variables `// ignore: unused_local_variable` que hacen trabajo de DB para nada) | `OfficialRepository.signaturesFor(matchId)`; borrar el código muerto |

> **Paso 0 obligatorio de la fase:** antes de tocar (b), capturar el payload real que hoy produce el mapper y guardarlo como fixture. El golden test compara byte a byte contra él. **Es la única garantía de que el backend PHP no note el cambio (I2).**

**Principio/patrón:** **DRY** · **SRP** · **Template Method** / **Strategy** para el flujo offline-first · **Mapper** puro (sin I/O ⇒ 100 % testeable).

**Tests:** golden del mapper contra el fixture capturado; `TempId` (negativo, monótono, único bajo concurrencia); `savePlayer` en los 3 escenarios (nube OK, nube caída→local, conflicto de dorsal con el workaround `+1000`/`9999`).

**Contrato externo:** máxima exposición a I2 en (b) y (d). Golden obligatorio antes y después.

**Criterio de salida:** los 5 bloques con 1 sola implementación; 0 `// ignore: unused_local_variable`; el golden del payload pasa **sin modificar el fixture**.

#### ✅ Resultado (2026-08-10)

| Métrica | Antes | Después |
|---|---|---|
| `flutter analyze` | 0 | **0** |
| `flutter test` | 152 verdes | **170 verdes** |
| `flutter build apk --release` | ✔ | ✔ 69.2 MB |
| Goldens de contrato (I2) | 35 ✔ | 35 ✔ + **golden del payload** |
| Esquema drift (I3) | — | `diff` vacío |
| Copias del mapper evento→payload | 2 | **1** |
| Copias de la subida offline de jugador | 2 | **1** |
| Estrategias de id temporal | 3 (en 7 sitios) | **1** |
| Copias de la bajada de calendario | 3 | **1** |
| Bloques duplicados del plan | 5 | **0** |
| `// ignore: unused_local_variable` | 1 | **0** |

**El paso 0 se hizo primero**, como manda el plan: el golden del payload se capturó **por el camino real** (`uploadPendingData()` contra BD en memoria + `MockClient`, comparando el cuerpo de la petición) y se commiteó **antes** de tocar el mapper. Pasa sin modificarse.

**Tres correcciones al diagnóstico de este plan:**

1. **El mapper de _rosters_ NO estaba duplicado.** El campo `played` se deriva de fuentes distintas a propósito: al cerrar el partido, de las estadísticas **vivas** en memoria (titular, en cancha, puntos, faltas); al subirlo más tarde, de si el jugador aparece en algún evento persistido, porque ya no hay estado en memoria. Unificarlos habría cambiado lo que se envía. Se comparte la **forma** (`mapRoster`) y `hasPlayed` se recibe como parámetro, con el porqué escrito en el código.

2. **Aparece una tercera copia del mapper** que el plan no listaba, en `home_menu_screen.exportMatchToJSON`. **Tampoco es la misma:** manda el `player_id` negativo tal cual (para corregirlo a mano en Postman), usa el `type` ya limpio y omite `clock_time`. Es un volcado de diagnóstico, no el acta. Se deja y se documenta.

3. **La duplicación (a) escondía un bug de integridad, no solo repetición.** Las dos copias no eran equivalentes: la del repositorio delega en `replaceTempPlayerId`, que en una transacción revincula `matchRosters`, `gameEvents.playerId` **y los ids incrustados en el texto de los eventos `SUB_A_OUT_<id>_IN_<id>`**. La de `starters_selection_screen` reconciliaba a mano y solo tocaba `players` y `gameEvents.playerId`: dejaba el acta con referencias a un jugador que ya no existía. Unificar **corrige esa corrupción**; hay un test que lo fija.

**La variante truncada de id temporal era un riesgo real:** `"-${...millisecondsSinceEpoch.toString().substring(5)}"` descarta los 5 primeros dígitos, dejando 8 cifras en vez de 13. Dos altas seguidas de sede u oficial podían generar el mismo id y pisarse. `TempId` además garantiza unicidad dentro del mismo milisegundo.

#### ✅ (c) cerrada — y tapaba un tercer bug

`FixtureRepository.refresh()` sustituye las 3 copias. Igual que en (a), **las copias no eran equivalentes**:

> `fixture_list_screen` **no ponía `isSynced`** al reinsertar. La columna toma su default (`false`) y `_uploadFixtures` recoge todo lo que esté en `false`, así que la siguiente sincronización **reenviaba al servidor partidos que acababan de venir de él**, como si fueran cambios locales de equipos. La otra copia sí lo marcaba.

Además, en las dos copias el `delete` quedaba **fuera** de la transacción: un fallo a mitad dejaba al usuario sin calendario. (Este sí era el problema de atomicidad real, no el que el plan señalaba en la Fase 5.)

El tercer sitio no persistía: solo recorría el mismo mapa de jornadas para contar enfrentamientos. Se comparte vía `scheduledTeamPairs`, que además descarta los `CANCELLED`.

| | Antes | Después |
|---|---|---|
| `fixture_list` refresh | 32 líneas | **15** |
| `manual_fixture_builder` reinserción | 34 líneas | **5** |
| `manual_fixture_builder` head-to-head | 27 líneas | **11** |

`fixture_list_screen` deja de importar drift: ya no toca la BD en ese flujo. 8 tests nuevos.

---

### Fase 7 — `MatchState` al dominio y contrato de marcador completo

**Objetivo:** invertir la dependencia `scoreboard → presentation` y arreglar la serialización con pérdida.

**Cambios:**

1. Extraer `MatchState` (+ `PlayerStats`, `ScoreEvent`) de `match_game_controller.dart` a `features/match/domain/entities/match_state.dart`. `scoreboard_payload.dart:4` pasa a importar `domain` en vez del controller ⇒ **se cumple la regla 1 de dependencias.**
2. **Separar el `toJson()` de doble propósito** (violación de ISP: hoy emite 14 de 30 campos y ese subconjunto es a la vez formato de cable y de persistencia):
   - `ScoreboardSnapshot` — DTO explícito y mínimo para el marcador.
   - `MatchStatePersistenceDto` — completo: incluye `matchId`, `playerStats`, `scoreLog`, rosters, `periodScores`, árbitros. **Se persiste en columnas ya existentes; no se agrega ninguna (I3).**

> **I4 — evolución aditiva, no versión nueva.** El plan original proponía `schemaVersion: 2`. Se rebaja a **campos aditivos opcionales sobre v1**, manteniendo `schemaVersion: 1`, de modo que una TV con la build vieja siga decodificando el payload de la build nueva. `scoreboard_payload.dart` ya tiene back-compat con el formato plano legacy: se replica ese criterio.

**Principio/patrón:** **DIP** (contrato de cable en el dominio) · **ISP** (un DTO por consumidor) · **SRP** · **DTO** + **evolución aditiva del esquema**.

**Tests:**
- Test de **completitud**: construir un `MatchState` con los 30 campos poblados, serializar a persistencia y afirmar igualdad tras deserializar. Falla si alguien agrega un campo y olvida el mapper.
- Test de **compatibilidad hacia atrás**: decodificar el payload **nuevo** con el parser **v1** capturado ⇒ debe funcionar (I4).
- Extender los tests existentes de `scoreboard_payload`.

**Contrato externo:** I2 intacto (esto no toca el backend). I3 intacto (sin columnas nuevas). I4 verificado por test.

**Criterio de salida:** `grep -rn "presentation" lib/features/scoreboard/domain` → 0; test de completitud verde; test v1 verde; **TV externa y tablet cliente verificadas en dispositivo contra una build anterior**, no solo entre dos builds nuevas.

**Rollback:** revert del commit. Al ser aditivo, no hay riesgo de dejar receptores incompatibles en campo.

#### ✅ Resultado (2026-08-10)

| Métrica | Antes | Después |
|---|---|---|
| `flutter analyze` | 0 | **0** |
| `flutter test` | 170 verdes | **183 verdes** |
| `flutter build apk --release` | ✔ | ✔ 69.2 MB |
| Goldens (I2 + acta + cable) | 37 | **45** |
| Esquema drift (I3) | — | `diff` vacío |
| Violaciones R3 | 4 | **2** |
| `scoreboard/domain` → `match/presentation` | 1 | **0** |
| Líneas de `match_game_controller.dart` | 1705 | **1596** |

**Corrección al plan.** El plan afirmaba que `MatchState.toJson()` era «a la vez el formato de cable y el de persistencia» y pedía partirlo en `ScoreboardSnapshot` + `MatchStatePersistenceDto`. **No es cierto:** lo usa únicamente `ScoreboardPayload`; el controller persiste en columnas de drift, no en JSON. Esos 14 de 30 campos no son una persistencia con pérdida — **son** el formato de cable, y el recorte es deliberado: `scoreLog` y `playerStats` son las listas más grandes del estado y el receptor no las necesita, porque las faltas se calculan en el emisor y viajan ya resueltas.

Así que en vez de inventar un DTO de persistencia que nadie pedía, la serialización se muda a `scoreboard/domain` como extensión `ScoreboardWire`. El recorte queda donde se decide, y añadir un campo a `MatchState` ya no cambia en silencio lo que se emite. **No se añaden campos de forma especulativa:** nada los consume hoy.

**Efecto en cadena:** seis archivos dejan de importar el controller (`pdf_generator`, `pdf_preview_screen`, `tv_scoreboard_widget` y tres tests). Solo querían la entidad.

Las dos violaciones R3 de `scoreboard/domain` eran únicamente `@immutable`: se cambia a `package:meta`, que es de donde viene la anotación. Las dos que quedan (`match_finalizer`, `open_finished_match_usecase`) son trabajo real de la Fase 8.

#### 🆕 `test/architecture_test.dart`

El plan describía las reglas de dependencia como «verificables por `grep`». Un `grep` que nadie ejecuta no protege nada: una regla que no falla en CI es documentación, no arquitectura. Ahora fallan solas, con su lista de excepciones **explícita y razonada**, e incluyen un test de que **la deuda conocida no crece** — si baja hay que actualizarla, así que el recuento del burn-down no puede mentir.

---

### Fase 8 — Romper `MatchGameController` (1.697 líneas / ~55 métodos)

**Objetivo:** la fase de mayor riesgo, deliberadamente al final, cuando ya hay tests y repositorios.

**División por responsabilidad** (`features/match/domain/engines/`, todos puros salvo persistencia):

| Componente | Responsabilidad |
|---|---|
| `GameClock` | `Timer`, tick, fin de periodo (hoy `Timer? _timer` vive fuera del state) |
| `ScoreEngine` | puntos, `scoreLog`, `periodScores` |
| `FoulEngine` | faltas personales y de equipo, bonus |
| `SubstitutionService` | rosters, titulares, workaround de dorsal `+1000`/`9999` |
| `MatchHistory` | pila de undo (hoy `List<MatchState> _history` fuera del state ⇒ undo no testeable) |
| `MatchPersistence` | escrituras drift |
| `MatchSyncCoordinator` | subida a la nube |

**Otros cambios:**
- `_isFinished` y `_history` entran al `MatchState` ⇒ el state deja de divergir de la instancia.
- `matchGameProvider` → `.family<MatchState, String matchId>` + `autoDispose`. Hoy es un provider global único: state obsoleto entre partidos, y es la causa de que `MatchFinalizer` dependa del controller concreto.
- `MatchFinalizer` pasa a depender de una **interfaz**, no de `MatchGameController`.
- El controller queda como orquestador delgado; **su API pública no cambia ⇒ ninguna pantalla se modifica.**

**Principio/patrón:** **SRP** (7 responsabilidades separadas) · **OCP** · **Facade** (el controller) · **Strategy** (reglas por torneo: periodos, bonus, tiempos muertos — hoy hardcodeadas) · **Memento** (undo) · **Command** (cada acción de usuario como evento).

**Tests:** `fake_async` para `GameClock` (fin de periodo, pausa/reanudación); unit test puro por engine; test de propiedad del undo (N acciones + N undos ⇒ state inicial); test de `matchGameProvider.family` con dos partidos simultáneos sin contaminación cruzada.

**Estrategia de ejecución:** **un engine por commit**, con el controller delegando desde el primero. Nunca un big-bang.

**Contrato externo:** I2 intacto (la subida a la nube pasa por el mapper ya congelado en Fase 6). I3 intacto.

**Criterio de salida:** `match_game_controller.dart` < 300 líneas; ningún engine > 250; `MatchFinalizer` no importa el controller; suite verde; **smoke manual de partido completo** (iniciar → faltas → cambios → tiempos muertos → undo → finalizar → PDF).

**Rollback:** por engine. Si un engine falla en campo se revierte ese commit y el controller vuelve a su implementación previa.

#### 🟡 En curso — 5 de 7 engines

| Métrica | Base | Ahora |
|---|---|---|
| `flutter analyze` | 0 | **0** |
| `flutter test` | 183 verdes | **250 verdes** |
| `flutter build apk --release` | ✔ | ✔ 69.2 MB |
| Esquema drift (I3) | — | `diff` vacío |
| Líneas de `match_game_controller.dart` | 1705 | **1399** |
| Engines extraídos | 0 | **5** |

| Engine | Qué era antes | Qué destapó |
|---|---|---|
| `ScoreEngine` | 96 líneas mezcladas con persistencia | Los rechazos eran `return` mudos **después** de guardar en la pila de deshacer: una acción rechazada la ensuciaba |
| `GameClock` | `Timer?` suelto; probar reglas exigía esperar segundos reales | Estrena `fake_async`. Cubre que arrancar dos veces no deje **dos** temporizadores (reloj al doble de velocidad) |
| `MatchHistory` | Lista suelta; deshacer sin tests pese a usarse en vivo | `TimeoutUndo` quita **ese** evento del log, no el último: entre medias puede haber canastas |
| `TimeoutEngine` | 3 métodos con un `if` de período cada uno | Lo que escribe acaba **impreso en el acta**. El minuto anotado no es un redondeo normal y es deliberado |
| `SubstitutionEngine` | 79 líneas con las ramas A y B duplicadas | Se aplicaba **a ciegas**: si el que salía no estaba en cancha, el entrante se añadía igual → **seis jugadores en cancha** |

**Un cambio de comportamiento deliberado**, en `SubstitutionEngine`: ahora valida y rechaza cambios ilegales. Se verificaron los dos llamadores antes de añadirlo — el diálogo de la UI elige de las listas de cancha/banca y `undoLastSub` invierte los papeles, así que ambos pasan cambios válidos; el restore usa otro método (`_applyRestoreSub`) y no pasa por aquí.

**Patrón común a los cinco:** cuando la operación no cambia nada devuelven `null` o `Rejected` en vez de un estado idéntico. Eso evita meter en la pila de deshacer pasos vacíos, que obligarían al anotador a pulsar deshacer dos veces.

**Corrección al plan:** el engine 4 se llamaba «`FoulEngine` (faltas de equipo y bonus)». Al abrir el código, el conjunto de reglas denso no son las faltas de equipo —que son casi triviales— sino los **tiempos muertos**. Se extrajo lo que de verdad tiene reglas.

#### ⬜ Faltan 2 engines y dos cambios estructurales

`MatchPersistence` y `MatchSyncCoordinator`. Y los dos de más riesgo, que tocan el ciclo de vida del partido: el paso a `matchGameProvider.family` + `autoDispose`, y romper la dependencia de `MatchFinalizer` sobre el controller — que es lo que cerraría las 2 violaciones R3 restantes.

---

### Fase 9 — Constantes, tema y calidad final

**Objetivo:** cerrar la deuda cosmética y subir el listón del analizador.

**Tareas:**
- 14 literales `'FINISHED'`/`'IN_PROGRESS'` → `MatchStatus`; 17 comparaciones `teamSide == 'A'` → `TeamSide` (adopción actual ~50 %).
- 21 `Color(0x...)` crudos → `AppColors`. `ThemeData` inline de `main.dart` → `app/theme/app_theme.dart`.
- `'[DEL]-'` (prefijo de borrado lógico en la columna de nombre) → `SoftDelete.prefix`.
- `pdf_generator.dart` (1.537 líneas, ~140 coordenadas `static const double`): extraer coordenadas a `ScoresheetLayout` y dividir en constructores de sección (`HeaderSection`, `PeriodTable`, `RosterTable`, `SignatureBlock`). Patrón **Builder/Composite**. Habilita un golden test de PDF (nº de páginas + extracción de texto).
- Eliminar los 3 `catch (_) {}` silenciosos y los `debugPrint`-y-continúa de `sync_repository.dart` (hoy `SyncResult` sub-reporta los conteos).
- Quitar los 5 `// ignore_for_file: use_build_context_synchronously` y arreglar los casos reales con `if (!context.mounted) return;`.
- **Corregir el solapamiento de `EventType`** detectado en la Fase 0: `isPlayerFoul('C')` e `isPlayerFoul('B')` devuelven `true` (por la regla `type.length <= 2`) **al mismo tiempo** que `isTeamFoul`. Una falta de banca en vivo se cuenta como falta personal de jugador si el filtro de `isPlayerFoul` corre primero. Con sufijo de lado (`'C_A'`) sí quedan separados. El comportamiento actual está congelado en `match_constants_test.dart`; ese test es la red al corregirlo.
- Activar las reglas diferidas de la Fase 0, en este orden (cada una en su propio commit, midiendo antes): `strict-casts` (119 errores hoy; debería caer solo tras la Fase 4), luego `strict-raw-types`, `strict-inference`, `avoid_dynamic_calls`, `prefer_final_locals`, `directives_ordering`, y `public_member_api_docs` solo en `domain/`.

**Contrato externo:** intacto. `SoftDelete.prefix` debe seguir siendo exactamente `'[DEL]-'` — es un dato que ya existe en las bases instaladas y en el backend (I2/I3).

**Criterio de salida:** `flutter analyze` con la configuración estricta = 0 issues; los conteos de grep del §0 en 0; `SyncResult` reporta números reales verificados por test.

---

### Fase 10 — Opcional, solo con disparador explícito

No ejecutar sin justificación escrita en §4.1.

| Cambio | Costo | Disparador que lo justificaría |
|---|---|---|
| `freezed` + `json_serializable` | 2 generadores más sobre un `build_runner` ya lento (`app_database.g.dart` = 10.864 líneas); reescritura de 8 modelos | Los modelos cambian >1 vez por sprint, o aparecen bugs de `copyWith`/igualdad |
| `riverpod_generator` + `riverpod_lint` | Reescritura de ~40 providers | Se suma un segundo desarrollador, o aparecen bugs de dependencias de providers |
| `integration_test` E2E | Requiere dispositivo o emulador en CI | Existe CI |
| CI (GitHub Actions: analyze + test + build) | Bajo | Recomendado en cuanto haya un segundo desarrollador o antes del primer release a Play Store |
| Flavors / `--dart-define` para `kServerBaseUrl` | Bajo | Se necesite un entorno de staging separado de producción |

---

## §4 — Control y seguimiento

### 4.1 Tabla de estado

Se actualiza al cerrar cada fase.

| Fase | Objetivo | Rama | Estado | `analyze` | `test` | Commit | Fecha |
|---|---|---|---|---|---|---|---|
| 0 | Red de seguridad + congelar contratos | `refactor/f0-safety-net` | ✅ Cerrada | 153 info / 0 err | 83 ✔ | — | 2026-08-09 |
| 1 | Mover archivos | `refactor/f1-mover-archivos` | 🟡 Verde, falta smoke en dispositivo | **0** | 83 ✔ | 7 commits | 2026-08-09 |
| 2 | DI + singletons | `refactor/f2-di` | 🟡 Verde, falta smoke en dispositivo | **0** | 93 ✔ | — | 2026-08-09 |
| 3 | Capa de red | `refactor/f3-network` + `f3.3-borrar-fachada` | 🟡 Verde, falta smoke en dispositivo | **0** | 105 ✔ | 5 commits | 2026-08-09 |
| 4 | Contratos de dominio | `refactor/f4-domain` | 🟡 Verde, falta smoke en dispositivo | **0** | 135 ✔ | 2 commits | 2026-08-10 |
| 5 | Sacar negocio de la UI | `refactor/f5-usecases` | 🟡 Verde, falta smoke en dispositivo | **0** | 152 ✔ | 3 commits | 2026-08-10 |
| 6 | Deduplicación | `refactor/f6-dry` + `f6c-fixture-refresh` | 🟡 Verde, falta smoke en dispositivo | **0** | 170 ✔ | 7 commits | 2026-08-10 |
| 7 | `MatchState` al dominio | `refactor/f7-match-state` | 🟡 Verde, falta smoke en dispositivo | **0** | 183 ✔ | 2 commits | 2026-08-10 |
| 8 | Dividir el controller | `refactor/f8-engines` | 🟡 5 de 7 engines | **0** | 250 ✔ | 7 commits | 2026-08-10 |
| 9 | Constantes y calidad | `refactor/f9-quality` | ⬜ Pendiente | — | — | — | — |
| 10 | Opcional | — | ⬜ No justificada | — | — | — | — |

Estados: ⬜ Pendiente · 🟡 En curso · ✅ Cerrada · 🔴 Revertida

### 4.2 Plantilla de checklist por fase

```markdown
### Fase N — <objetivo>
Rama: `refactor/fN-<slug>` · Commit: `<sha>` · Estado: 🟡

- [ ] Baseline registrada (analyze: __ issues / test: __ verdes)
- [ ] Tarea 1
- [ ] Tarea 2
- [ ] Tests nuevos escritos y en verde
- [ ] DoD 1 — `flutter analyze` sin issues nuevos
- [ ] DoD 2 — `flutter test` 100 % verde
- [ ] DoD 3 — `flutter build apk --release` compila (I1)
- [ ] DoD 4 — golden de peticiones HTTP sin diferencias (I2)
- [ ] DoD 5 — diff de esquema drift vacío + schemaVersion sin cambios (I3)
- [ ] DoD 6 — smoke manual de los 4 flujos críticos
- [ ] DoD 7 — smoke de actualización in-place (instalar encima, datos intactos)
- [ ] DoD 8 — criterio de salida verificado por grep
- [ ] Merge a `main`

**Rollback:** `git branch -D refactor/fN-<slug>` (sin mergear) · o `git revert <sha>`.
**Notas / desviaciones:**
```

### 4.3 Definition of Done

Una fase **no se mergea** si falla cualquiera de estos 8 puntos:

1. `flutter analyze` sin issues nuevos respecto a la línea base de la fase anterior.
2. `flutter test` 100 % verde, con al menos un test nuevo que cubra lo que la fase cambió.
3. `flutter build apk --release` compila ⇒ **la fase es publicable (I1)**.
4. **Golden de peticiones HTTP sin diferencias ⇒ backend intacto (I2).**
5. **`diff` del dump de esquema drift vacío y `schemaVersion` sin cambios ⇒ base de datos intacta (I3).**
6. Smoke manual de los 4 flujos críticos: crear partido · jugar y finalizar · generar PDF · marcador en TV externa.
7. **Smoke de actualización in-place:** instalar el APK de la fase **encima** de la build anterior (sin desinstalar) y comprobar que los partidos, equipos y jugadores previos siguen ahí ⇒ confirma I3 sobre datos reales.
8. Criterio de salida de la fase verificado por `grep`.

**Comandos que se corren antes y después de cada fase:**

```bash
flutter pub get
flutter analyze
flutter test
dart format <solo los archivos que la fase creó o tocó>       # ver nota
flutter build apk --release                                   # DoD 3, toda fase
dart run drift_dev schema dump lib/core/database/app_database.dart schema/current.json
diff schema/base.json schema/current.json                     # debe ser vacío
```

> **Esta regla se incumplió en la Fase 3.3 y salió caro.** Correr `dart format` sobre `lib/` reformateó 54 archivos (**+5867/−3602**) para ~50 cambios reales: `match_control_screen.dart` salía con **+1996/−723** por UNA línea, y `tv_scoreboard_widget.dart` aparecía en el commit sin haberlo tocado. Además el reformateo partió `if (x) stmt;` en dos líneas, lo que disparó 9 `curly_braces_in_flow_control_structures` que antes no existían. Hubo que reconstruir el commit desde el estado limpio reaplicando solo lo funcional: **21 archivos, +1211/−995**. No repetir.

> **Nota sobre `dart format` (medido en Fase 0):** `dart format lib test` reformatea **66 de 76 archivos** — el "tall style" del formatter de Dart 3.10 toca casi todo el código existente. Correrlo de forma global está **prohibido en la Fase 1**: destruiría la verificación `added == deleted` del diff, que es la única prueba de que no se coló lógica. Se formatean solo los archivos nuevos de cada fase. El reformateo global, si se quiere, va en la Fase 9 como commit propio y aislado.

### 4.4 Burn-down de deuda

Columna **Base** = medido antes de la Fase 0. Se llena una columna al cerrar cada fase marcada.

| Métrica | Base | F0 | F1 | F2 | F3 | F4 | F5 | F8 | Meta |
|---|---|---|---|---|---|---|---|---|---|
| Líneas de `match_game_controller.dart` | 1697 | 1697 | 1697 | 1697 | 1697 | 1697 | 1705 |  | <300 |
| Métodos de `ApiService` | 30 | 30 | 30 | 30 | **0 (borrada)** | 0 | 0 |  | 0 |
| Acciones `action=` del backend | 30 | 30 ✔ congeladas | 30 ✔ | 30 ✔ | 30 ✔ | 30 ✔ | 30 ✔ |  | 30 |
| Providers duplicados | 2 | 2 | 2 | **0** | 0 | 0 | 0 |  | 0 |
| Providers declarados en widgets | 3 | 3 | 3 | **0** | 0 | 0 | 0 |  | 0 |
| Violaciones R2 (`core`/`shared` → `features`) | — | — | 3 | 3 | **2** | **1** ✔ | 1 ✔ |  | 1 (solo el composition root) |
| Violaciones R3 (`domain` → flutter/drift/http) | — | — | 3 | 3 | 3 | 3 | 3 |  | 0 |
| Violaciones R4 (`presentation` → db/api) | 7+7 | 14 | **10** | 10 | 10 | 10 | 12 |  | 0 |
| Bloques de código duplicados | 5 | 5 | 5 | 5 | 5 | 5 | 4 |  | 0 |
| Imports relativos | 136 | 136 | **0** | 0 | 0 | 0 | 0 |  | 0 |
| Literales `'FINISHED'`/`'IN_PROGRESS'` | 14 | 14 | 14 | 14 | 14 | 14 | 14 |  | 0 |
| `teamSide == 'A'` crudos | 17 | 17 | 17 | 17 | 17 | 17 | 17 |  | 0 |
| `Color(0x...)` fuera de `AppColors` | 21 | 21 | 21 | 21 | 21 | 21 | 21 |  | 0 |
| Imports con alias `as catalog`/`as model` | 4 | 4 | 4 | 4 | 4 | **0** | 0 |  | 0 |
| Tests verdes | 29 (+1 rojo) | **83** | 83 | **93** | **105** | **135** | **152** |  | ≥200 |
| Archivos de test | 6 (1 roto) | **8** | 8 | **10** | **11** | **14** | **17** |  | ≥40 |
| `flutter analyze` — errores | 0 | **0** | **0** | 0 | 0 | 0 | 0 |  | 0 |
| `flutter analyze` — info | 5 | 153 | **0** | 0 | 0 | 0 | 0 |  | 0 |
| Singletons estáticos (`.instance`) | 3 | 3 | 3 | **0** | 0 | 0 | 0 |  | 0 |
| `http.get`/`http.post` top-level | 30 | 30 | 30 | 30 | **0** | 0 | 0 |  | 0 |
| Copias del chequeo de status HTTP | ~20 | ~20 | ~20 | ~20 | **0** | 0 | 0 |  | 0 |
| Líneas de `ApiService` | 866 | 866 | 866 | 866 | **0** | 0 | 0 |  | 0 |

---

## §5 — Riesgos y mitigaciones

| Riesgo | Fase | Mitigación |
|---|---|---|
| `secondaryDisplayMain` deja de resolverse ⇒ TV en negro | 1 | No se toca `main.dart`; smoke con HDMI/AnyCast obligatorio en las fases 1, 2 y 7 |
| `.g.dart` de drift con rutas rotas al mover `database/` | 1 | `dart run build_runner build --delete-conflicting-outputs` y commitear el generado en la misma fase |
| Se cuela un cambio de lógica en la fase "solo mover" | 1 | `git diff -M --numstat`: `added == deleted` en todo archivo modificado |
| Cambio de payload rompe el backend PHP (I2) | 3, 4, 6 | 34 goldens `(url, método, headers, body/fields/files)` capturados en Fase 0; se corren en **cada commit**, no solo al cerrar fase |
| Regeneración de `.g.dart` altera el esquema o dispara una migración (I3) | 1, 2 | `diff` del dump contra `schema/base.json` + test de `schemaVersion` + smoke de instalación encima de la build anterior |
| Build nueva emite un payload que la TV con build vieja no decodifica (I4) | 7 | Solo campos aditivos opcionales, `schemaVersion: 1` intacto; test que decodifica el payload nuevo con el parser v1 |
| Una fase queda a medias y `main` no es publicable (I1) | todas | Rama por fase; merge solo con los 8 puntos del DoD en verde; `flutter build apk --release` es requisito, no opcional |
| drift en memoria no arranca en `flutter test` (Windows) | 2 | Decidir en la fase: `sqlite3.dll` en la raíz **o** fakes de mocktail sobre la interfaz del DAO |
| Dividir el controller rompe un partido en vivo | 8 | Un engine por commit; API pública del controller intacta; smoke de partido completo por commit |
