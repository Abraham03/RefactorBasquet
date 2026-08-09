import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/features/teams/data/repositories/player_repository.dart';
import 'package:myapp/features/match/domain/services/outcome_changer.dart';
import 'package:myapp/features/match/presentation/controllers/match_game_controller.dart';
import 'package:myapp/core/database/app_database.dart';
import 'package:myapp/core/network/api_service.dart';
import 'package:myapp/features/catalog/data/repositories/sync_repository.dart';
import 'package:myapp/features/match/data/repositories/official_repository.dart';
import 'package:myapp/features/match/domain/services/match_finalizer.dart';
import 'package:myapp/features/match/data/repositories/attendance_repository.dart';


// Provider de la Base de Datos (Singleton)
// Equivalente a un @Bean en Spring
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

// Provider del DAO de Partidos
final matchesDaoProvider = Provider((ref) {
  final db = ref.watch(databaseProvider);
  return db.matchesDao;
});

// Esto crea la variable 'apiServiceProvider' que te faltaba
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