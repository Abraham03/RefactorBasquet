// Arnés de captura de peticiones HTTP para el invariante I2 del
// "Plan Estructura Limpia.md": el contrato con el backend PHP es intocable.
//
// `ApiService` usa las funciones top-level `http.post` / `http.get`, que no
// admiten inyección de un cliente. Pero `package:http` >= 1.0 expone
// `runWithClient`, que instala un `Client` en la zona actual: tanto las
// funciones top-level como `BaseRequest.send()` (multipart) lo consultan.
// Eso permite capturar la petición REAL sin tocar una línea de producción.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Petición capturada, normalizada para poder compararse byte a byte
/// entre corridas y entre fases del refactor.
class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
    this.fields,
    this.files,
  });

  final String method;
  final String url;
  final Map<String, String> headers;

  /// Cuerpo de una petición normal (`http.Request`).
  final String? body;

  /// Campos de una petición multipart.
  final Map<String, String>? fields;

  /// Metadatos de los archivos adjuntos de una petición multipart.
  final List<Map<String, Object?>>? files;

  Map<String, Object?> toJson() => {
    'method': method,
    'url': url,
    'headers': headers,
    if (body != null) 'body': _prettyIfJson(body!),
    if (fields != null)
      'fields': fields!.map((k, v) => MapEntry(k, _prettyIfJson(v))),
    if (files != null) 'files': files,
  };

  /// El body y los campos multipart llevan JSON serializado. Decodificarlo
  /// hace que el golden sea legible y que un diff señale la clave exacta que
  /// cambió, en vez de una sola línea gigante.
  static Object? _prettyIfJson(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return raw;
    }
  }
}

/// Cliente que registra cada petición y devuelve siempre la misma respuesta.
///
/// La respuesta es irrelevante para I2: lo que se congela es la petición.
/// Se responde algo genéricamente parseable para que los métodos avancen lo
/// más lejos posible, pero el llamador debe envolver cada invocación en
/// try/catch porque muchos métodos de `ApiService` lanzan al parsear.
class RecordingClient extends http.BaseClient {
  RecordingClient({
    this.responseBody = _defaultResponse,
    this.statusCode = 200,
  });

  static const String _defaultResponse =
      '{"status":"success",'
      '"message":"ok",'
      '"data":{"newId":"1","id":"1","fixture_id":"1",'
      '"real_score_a":0,"real_score_b":0,'
      '"tournaments":[],"venues":[],"teams":[],"players":[],'
      '"tournament_teams":[],"officials":[],"fixtures":[],'
      '"finished_rosters":[]}}';

  final String responseBody;
  final int statusCode;

  final List<CapturedRequest> captured = <CapturedRequest>[];

  /// La última petición capturada. Falla si no hubo ninguna.
  CapturedRequest get last {
    if (captured.isEmpty) {
      throw StateError('No se capturó ninguna petición.');
    }
    return captured.last;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    captured.add(_capture(request));

    final bytes = utf8.encode(responseBody);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      contentLength: bytes.length,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }

  CapturedRequest _capture(http.BaseRequest request) {
    final headers = _normalizeHeaders(request.headers);

    if (request is http.MultipartRequest) {
      return CapturedRequest(
        method: request.method,
        url: request.url.toString(),
        headers: headers,
        fields: Map<String, String>.from(request.fields),
        // No se consume el stream del archivo: se registran sus metadatos,
        // que es lo que define el contrato con el backend.
        files: request.files
            .map(
              (f) => <String, Object?>{
                'field': f.field,
                'filename': f.filename,
                'contentType': f.contentType.toString(),
                'length': f.length,
              },
            )
            .toList(),
      );
    }

    return CapturedRequest(
      method: request.method,
      url: request.url.toString(),
      headers: headers,
      body: request is http.Request ? request.body : null,
    );
  }

  /// El boundary de multipart es aleatorio en cada corrida y `content-length`
  /// se deriva del body. Se normalizan para que el golden sea estable.
  static Map<String, String> _normalizeHeaders(Map<String, String> raw) {
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'content-length') continue;
      var value = entry.value;
      if (key == 'content-type' && value.contains('boundary=')) {
        value = value.replaceAll(
          RegExp(r'boundary=[^;]+'),
          'boundary=<random>',
        );
      }
      out[key] = value;
    }
    return out;
  }
}
