import 'package:flutter/material.dart';

/// Tema de la app.
///
/// Estaba inline dentro del `build` de `MyApp`, así que se reconstruía en cada
/// rebuild del widget raíz. Aquí es `static final`: se crea una vez.
///
/// **Ojo con lo que este tema NO controla.** La mayoría de las pantallas
/// pintan sus colores a mano sobre fondo oscuro (ver `AppColors`), mientras
/// que este `ColorScheme` es claro. No es una incoherencia que se pueda
/// arreglar cambiando `brightness`: hay que migrar las pantallas primero, o
/// se quedan textos blancos sobre fondo blanco. Queda fuera de la Fase 9.
abstract final class AppTheme {
  static final ThemeData light = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepOrange,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: Colors.grey.shade50,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
