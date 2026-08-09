// lib/ui/widgets/app_network_image.dart
import 'package:flutter/material.dart';

import 'package:myapp/core/utils/image_url_resolver.dart';

/// Imagen remota del backend con resolución de ruta y fallback garantizados.
///
/// No lleva lógica de formato: Skia/Impeller (y el navegador en web) decodifican
/// WebP, PNG, JPEG y GIF de forma nativa. Lo que este widget centraliza es la
/// resolución de la ruta relativa y el hecho de que **siempre** haya un
/// placeholder, de modo que un 404 durante la migración degrade con elegancia.
class AppNetworkImage extends StatelessWidget {
  /// Ruta cruda tal como llega del backend (relativa o absoluta).
  final String? rawPath;

  /// Se usa cuando no hay ruta o cuando la carga falla. Obligatorio a propósito.
  final WidgetBuilder fallbackBuilder;

  final BoxFit fit;
  final Alignment alignment;

  /// Ancho en píxeles lógicos con el que se dibuja la imagen. Si se indica, se
  /// decodifica a esa resolución en vez de a la del archivo original, lo que
  /// recorta el uso del `ImageCache`.
  final double? displayWidth;

  /// Si se indica, se muestra un spinner de este color mientras carga.
  final Color? loadingColor;

  const AppNetworkImage({
    super.key,
    required this.rawPath,
    required this.fallbackBuilder,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.displayWidth,
    this.loadingColor,
  });

  @override
  Widget build(BuildContext context) {
    final url = ImageUrlResolver.resolve(rawPath);
    if (url == null) return fallbackBuilder(context);

    final width = displayWidth;
    final cacheWidth = width == null
        ? null
        : (width * MediaQuery.devicePixelRatioOf(context)).round();

    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      cacheWidth: cacheWidth,
      errorBuilder: (context, error, stackTrace) => fallbackBuilder(context),
      loadingBuilder: loadingColor == null
          ? null
          : (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: loadingColor,
                    strokeWidth: 2,
                  ),
                ),
              );
            },
    );
  }
}
