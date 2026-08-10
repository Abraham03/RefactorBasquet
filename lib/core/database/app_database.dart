import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
// Importamos las tablas y DAOs
import 'package:myapp/core/database/tables/app_tables.dart';
import 'package:myapp/core/database/daos/matches_dao.dart';

part 'app_database.g.dart'; // Archivo generado automáticamente

@DriftDatabase(tables: [
  Matches, 
  Players, 
  MatchRosters, 
  GameEvents, 
  Tournaments , 
  Venues, 
  Teams, 
  TournamentTeams,
  Fixtures,
  Officials,
  ],
  daos: [MatchesDao], // Registramos el DAO
)
class AppDatabase extends _$AppDatabase {
  /// El ciclo de vida lo gestiona `databaseProvider` (core/di/providers.dart),
  /// que es el único que debe construirla.
  ///
  /// Antes esto era un singleton duro (`static final _instance` +
  /// `factory AppDatabase()`), lo que hacía inútil cualquier
  /// `databaseProvider.overrideWith(...)` en un test: se devolvía siempre la
  /// misma instancia de proceso, apuntando al .sqlite real del dispositivo.
  AppDatabase() : super(_openConnection());

  /// Conexión inyectada para tests (p.ej. `NativeDatabase.memory()`).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  // Migraciones: Aquí manejarás cambios futuros de esquema
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Ejemplo: si en la v2 agregas una columna
       if (from < 2) await m.addColumn(matchRosters, matchRosters.isStarter);
       if (from < 3) {
         await m.addColumn(matches, matches.clockTime);
         await m.addColumn(matches, matches.currentPeriod);
       }
       if (from < 4) await m.addColumn(matchRosters, matchRosters.attended);
    },
  );
}

// Función para abrir la conexión nativa
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // 1. Obtener la carpeta de documentos de la app
    final dbFolder = await getApplicationDocumentsDirectory();
    
    // 2. Crear la referencia al archivo
    final file = File(p.join(dbFolder.path, 'basketball_league.sqlite'));

    // createInBackground a veces da problemas en release si no se configura bien el ProGuard
    // logStatements solo en debug: en release volcaba cada sentencia SQL al log
    // del dispositivo (ruido y fuga de datos del partido).
    return NativeDatabase(file, logStatements: !kReleaseMode);
  });
}
