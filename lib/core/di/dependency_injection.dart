import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/data/repositories/player_repository.dart';
import 'package:myapp/logic/match_game_controller.dart';
import '../database/app_database.dart';
import '../service/api_service.dart';
import '../../data/repositories/sync_repository.dart';
import '../../data/repositories/official_repository.dart';
import '../../domain/services/match_finalizer.dart';


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