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
import 'package:myapp/core/network/api_service.dart';
import 'package:myapp/features/catalog/data/repositories/sync_repository.dart';
import 'package:myapp/features/match/data/repositories/official_repository.dart';
import 'package:myapp/features/match/domain/services/match_finalizer.dart';
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

/// Cliente del backend.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});


/// Repositorio de sincronización (orquesta la subida a la nube).
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final api = ref.watch(apiServiceProvider);
  final matchesDao = ref.watch(matchesDaoProvider);
  return SyncRepository(db, api, matchesDao);
});

final officialRepositoryProvider = Provider<OfficialRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return OfficialRepository(db);
});

final matchFinalizerProvider = Provider<MatchFinalizer>((ref) {
  final db = ref.watch(databaseProvider);
  final api = ref.watch(apiServiceProvider);
  final officialRepo = ref.watch(officialRepositoryProvider);
  final controller = ref.watch(matchGameProvider.notifier);
  return MatchFinalizer(db, api, officialRepo, controller);
});

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final api = ref.watch(apiServiceProvider);
  return PlayerRepository(db, api);
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(matchesDaoProvider), ref.watch(apiServiceProvider));
});

final outcomeChangerProvider = Provider<OutcomeChanger>((ref) {
  return OutcomeChanger(ref.watch(apiServiceProvider));
});