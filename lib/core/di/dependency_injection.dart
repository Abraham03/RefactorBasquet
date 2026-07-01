import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';
import '../service/api_service.dart';
import '../../data/repositories/sync_repository.dart';


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