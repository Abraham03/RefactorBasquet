import 'package:flutter/material.dart';

/// Paleta del marcador de TV.
///
/// **Por qué no vive en `AppColors`.** No es la identidad visual de la app:
/// es una paleta de alto contraste pensada para leerse desde la grada, en un
/// televisor que puede estar mal calibrado y a varios metros. El negro es más
/// profundo que el fondo de la app y los acentos son más saturados. Meterlos
/// en `AppColors` invitaría a usarlos en pantallas normales, donde chirrían.
///
/// Los nombres describen la **función**, no el color, para que retocar la
/// paleta no obligue a renombrar nada.
abstract final class ScoreboardColors {
  /// Fondo del marcador. Negro mate, más profundo que el de la app: en un
  /// panel grande un gris se ve sucio.
  static const Color background = Color(0xFF050505);

  /// Fondo de los bloques interiores (reloj, período).
  static const Color panel = Color(0xFF151515);

  /// Reloj corriendo. Se apaga a `Colors.red.shade900` al pararse.
  static const Color clockRunning = Color(0xFFFF3131);

  // --- Equipos ---
  // Azul y rosa en el banner del nombre; cian y magenta en los dígitos del
  // marcador, que necesitan más brillo para leerse a distancia.

  static const Color teamABanner = Color(0xFF0066FF);
  static const Color teamBBanner = Color(0xFFD81B60);
  static const Color teamAScore = Color(0xFF00D4FF);
  static const Color teamBScore = Color(0xFFFF1E63);

  /// Flecha de posesión activa. Verde neón, el mismo de la app.
  static const Color possession = Color(0xFFCCFF00);
}
