import 'package:flutter/material.dart';

/// Paleta de colores de marca de Van Ball.
///
/// Centraliza los colores propios (hex) que estaban repartidos como
/// literales por toda la UI. Los colores estándar de Flutter
/// (Colors.white, Colors.redAccent, etc.) se siguen usando directos:
/// esta clase es solo para la identidad visual de la app.
///
/// Uso: AppColors.surface, AppColors.background, etc.
abstract final class AppColors {
  // --- Superficies oscuras (fondos de tarjetas, diálogos, sheets) ---

  /// Fondo principal de la app / superficies más oscuras. (0xFF0D1117)
  static const Color background = Color(0xFF0D1117);

  /// Superficie de tarjetas y diálogos. El más usado. (0xFF1A1F2B)
  static const Color surface = Color(0xFF1A1F2B);

  /// Superficie elevada (bottom sheets, menús, variante de tarjeta). (0xFF1E2432)
  static const Color surfaceVariant = Color(0xFF1E2432);

  /// Superficie de dropdowns / inputs sobre fondo oscuro. (0xFF2C323F)
  static const Color surfaceInput = Color(0xFF2C323F);

  /// Placeholder de fotos / avatares vacíos. (0xFF252A36)
  static const Color surfacePlaceholder = Color(0xFF252A36);

  // --- Acentos de marca específicos (no estándar de Flutter) ---

  /// Verde lima de posesión (icono de balón activo). (0xFFCCFF00)
  static const Color possession = Color(0xFFCCFF00);

  // --- Colores de acento semánticos (alias de los de Flutter) ---
  // Se exponen como alias para que el día que quieras cambiar el acento
  // primario de naranja a otro color, sea un solo cambio aquí.

  /// Acento primario de la marca (equipo A, botones de acción).
  static const Color primary = Colors.orangeAccent;

  /// Acento secundario (equipo B).
  static const Color secondary = Colors.lightBlueAccent;
}