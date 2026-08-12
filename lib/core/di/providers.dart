/// Composition root de la app: la ÚNICA fuente de cada dependencia.
///
/// Antes `databaseProvider` y `apiServiceProvider` estaban declarados también
/// en los providers de catalog y tournament, así que convivían dos instancias
/// distintas de `ApiService` y las pantallas usaban una u otra sin criterio.
///
/// Este es el único archivo de `core/` al que se le permite importar
/// `features/` (regla 2 del plan): un composition root, por definición, conoce
/// todo lo que cablea.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/database/daos/matches_dao.dart';
import 'package:myapp/features/teams/data/repositories/player_repository.dart';
import 'package:myapp/features/match/domain/services/outcome_changer.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/features/catalog/data/datasources/catalog_api.dart';
import 'package:myapp/features/fixture/data/datasources/fixture_api.dart';
import 'package:myapp/features/fixture/data/repositories/fixture_repository.dart';
import 'package:myapp/features/match/data/datasources/match_api.dart';
import 'package:myapp/features/match/data/datasources/official_venue_api.dart';
import 'package:myapp/features/teams/data/datasources/team_api.dart';
import 'package:myapp/features/catalog/data/repositories/catalog_download_repository.dart';
import 'package:myapp/features/catalog/data/repositories/sync_repository.dart';
import 'package:myapp/shared/services/image_store.dart';
import 'package:myapp/features/match/data/repositories/drift_match_closing_repository.dart';
import 'package:myapp/features/match/data/repositories/official_repository.dart';
import 'package:myapp/features/match/domain/repositories/match_closing_repository.dart';
import 'package:myapp/features/match/domain/repositories/official_repository_contract.dart';
import 'package:myapp/features/match/domain/services/match_finalizer.dart';
import 'package:myapp/features/match/data/repositories/finished_match_loader.dart';
import 'package:myapp/features/match/data/repositories/attendance_repository.dart';

/// Base de datos local. Su ciclo de vida cuelga del contenedor: al desecharse
/// el `ProviderScope` se cierra la conexión.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// DAO de partidos.
final matchesDaoProvider = Provider<MatchesDao>((ref) {
  return ref.watch(databaseProvider).matchesDao;
});

/// Transporte HTTP. Una sola instancia: comparte el pool de conexiones.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

// --- Los cinco datasources en los que se dividió la vieja God class ---

final catalogApiProvider = Provider<CatalogApi>(
  (ref) => CatalogApi(ref.watch(apiClientProvider)),
);

final fixtureApiProvider = Provider<FixtureApi>(
  (ref) => FixtureApi(ref.watch(apiClientProvider)),
);

final teamApiProvider = Provider<TeamApi>(
  (ref) => TeamApi(ref.watch(apiClientProvider)),
);

final matchApiProvider = Provider<MatchApi>(
  (ref) => MatchApi(ref.watch(apiClientProvider)),
);

final officialVenueApiProvider = Provider<OfficialVenueApi>(
  (ref) => OfficialVenueApi(ref.watch(apiClientProvider)),
);

/// Calendario local: bajada desde la nube y consultas derivadas.
final fixtureRepositoryProvider = Provider<FixtureRepository>((ref) {
  return FixtureRepository(
    ref.watch(databaseProvider),
    ref.watch(fixtureApiProvider),
  );
});

/// Sincronización de bajada: descarga el catálogo y reemplaza el local.
final catalogDownloadRepositoryProvider = Provider<CatalogDownloadRepository>((
  ref,
) {
  return CatalogDownloadRepository(
    ref.watch(databaseProvider),
    ref.watch(catalogApiProvider),
    // Aprovecha la descarga —que siempre es con red— para dejar los logos del
    // acta en disco. Es el mismo almacén que consulta el generador de PDF.
    logoCache: AppImageStores.logos,
  );
});

/// Repositorio de sincronización (orquesta la subida a la nube).
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  return SyncRepository(
    ref.watch(databaseProvider),
    ref.watch(matchesDaoProvider),
    playerRepository: ref.watch(playerRepositoryProvider),
    catalogApi: ref.watch(catalogApiProvider),
    officialVenueApi: ref.watch(officialVenueApiProvider),
    teamApi: ref.watch(teamApiProvider),
    fixtureApi: ref.watch(fixtureApiProvider),
    matchApi: ref.watch(matchApiProvider),
  );
});

/// Se expone por su CONTRATO, no por la clase concreta: así el dominio
/// (`MatchFinalizer`) no queda atado a la implementación que abre drift.
final officialRepositoryProvider = Provider<OfficialRepositoryContract>((ref) {
  return OfficialRepository(ref.watch(databaseProvider));
});

final matchClosingRepositoryProvider = Provider<MatchClosingRepository>(
  (ref) => DriftMatchClosingRepository(ref.watch(databaseProvider)),
);

final matchFinalizerProvider = Provider<MatchFinalizer>((ref) {
  return MatchFinalizer(
    ref.watch(matchClosingRepositoryProvider),
    ref.watch(matchApiProvider),
    ref.watch(teamApiProvider),
    ref.watch(officialRepositoryProvider),
    ref.watch(matchGameProvider.notifier),
  );
});

/// Prepara un partido finalizado para corregir su resultado.
final finishedMatchLoaderProvider = Provider<FinishedMatchLoader>((ref) {
  return FinishedMatchLoader(
    ref.watch(databaseProvider),
    ref.watch(matchApiProvider),
    ref.watch(officialRepositoryProvider),
  );
});

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  return PlayerRepository(
    ref.watch(databaseProvider),
    ref.watch(teamApiProvider),
    ref.watch(matchesDaoProvider),
  );
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(
    ref.watch(matchesDaoProvider),
    ref.watch(matchApiProvider),
  );
});

final outcomeChangerProvider = Provider<OutcomeChanger>((ref) {
  return OutcomeChanger(ref.watch(matchApiProvider));
});
