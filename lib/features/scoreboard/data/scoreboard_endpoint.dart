/// Punto único de verdad para los puertos y URIs del marcador.
///
/// Antes el `8080` estaba escrito a mano en tres archivos distintos
/// (servidor, receptor de pantalla externa y cliente por IP), así que cambiar
/// de puerto exigía tocar los tres y no había forma de tener respaldo.
abstract final class ScoreboardEndpoint {
  /// Se prueban en orden. El servidor toma el primero libre; los clientes los
  /// recorren hasta encontrar quién responde.
  static const List<int> candidatePorts = [8080, 8081, 8082];

  static const String loopbackHost = '127.0.0.1';

  static int get defaultPort => candidatePorts.first;

  /// Candidatos para el isolate de la pantalla externa. Ese isolate no comparte
  /// memoria con el principal, así que no puede saber en qué puerto acabó el
  /// servidor: los recorre hasta acertar.
  static List<Uri> loopbackCandidates() =>
      [for (final p in candidatePorts) Uri.parse('ws://$loopbackHost:$p')];

  /// Acepta `192.168.1.5`, `192.168.1.5:8081`, `ws://192.168.1.5:8080`.
  /// Devuelve `null` si no se puede interpretar.
  static Uri? parseUserInput(String raw) {
    var input = raw.trim();
    if (input.isEmpty) return null;

    if (input.startsWith('ws://') || input.startsWith('wss://')) {
      final uri = Uri.tryParse(input);
      if (uri == null || uri.host.isEmpty) return null;
      return uri.hasPort ? uri : uri.replace(port: defaultPort);
    }

    // Rechaza esquemas que no sean WebSocket antes de tratarlo como host.
    if (input.contains('://')) return null;

    int port = defaultPort;
    if (input.contains(':')) {
      final parts = input.split(':');
      if (parts.length != 2) return null;
      final parsedPort = int.tryParse(parts[1]);
      if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
        return null;
      }
      input = parts[0];
      port = parsedPort;
    }

    if (!_isValidHost(input)) return null;
    return Uri(scheme: 'ws', host: input, port: port);
  }

  /// Mensaje para el usuario, o `null` si la entrada es válida.
  static String? validationError(String raw) {
    if (raw.trim().isEmpty) return 'Escribe la IP del dispositivo Árbitro.';
    return parseUserInput(raw) == null
        ? 'IP inválida. Ejemplo: 192.168.1.5 o 192.168.1.5:8081'
        : null;
  }

  /// Todos los puertos candidatos para un host dado, empezando por el que el
  /// usuario indicó explícitamente (si lo hizo).
  static List<Uri> candidatesForInput(String raw) {
    final primary = parseUserInput(raw);
    if (primary == null) return const [];
    final explicitPort = raw.contains(':');
    if (explicitPort) return [primary];
    return [
      for (final p in candidatePorts) primary.replace(port: p),
    ];
  }

  static bool _isValidHost(String host) {
    if (host.isEmpty) return false;
    final octets = host.split('.');
    if (octets.length == 4 && octets.every((o) => int.tryParse(o) != null)) {
      return octets.every((o) {
        final v = int.parse(o);
        return v >= 0 && v <= 255;
      });
    }
    // Permite nombres de host (mDNS, "localhost", etc.).
    return RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-.]*[a-zA-Z0-9])?$').hasMatch(host);
  }
}
