import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:myapp/core/constants/api_constants.dart';
import 'package:myapp/core/errors/app_exception.dart';
import 'package:myapp/core/network/connectivity_helper.dart';
import 'package:myapp/core/network/result.dart';

/// Transporte HTTP hacia el backend PHP.
///
/// Concentra lo que estaba inlineado en los 30 métodos de `ApiService`:
/// construir la URL, poner el `Content-Type`, comprobar el status (`_checkResponse`
/// existía pero solo lo llamaban 5 de 30 métodos; los otros 25 repetían
/// `if (statusCode == 200 || statusCode == 201)`), decodificar el sobre JSON
/// `{status, message, data}` y traducir el fallo a una `AppException`.
///
/// **El `http.Client` se inyecta.** Antes se usaban las funciones top-level
/// `http.post` / `http.get`, que no admiten sustitución: por eso la capa de red
/// no se podía testear.
///
/// **Invariante I2:** las peticiones que emite deben ser byte-idénticas a las
/// que emitía `ApiService`. Los goldens de `api_contract_golden_test.dart` lo
/// vigilan en cada commit.
class ApiClient {
  ApiClient({
    http.Client? client,
    this.baseUrl = kApiEndpoint,
    this.timeout = const Duration(seconds: 30),
    this.uploadTimeout = const Duration(minutes: 3),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// Antes no había ningún timeout: una red que aceptaba la conexión pero no
  /// respondía dejaba la app colgada indefinidamente con el loader puesto.
  final Duration timeout;

  /// Más holgado para multipart: subir el PDF del acta por datos móviles
  /// legítimamente tarda.
  final Duration uploadTimeout;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  void close() => _client.close();

  // ---------------------------------------------------------------------------
  // Peticiones
  // ---------------------------------------------------------------------------

  /// GET con la acción y los parámetros en la query string.
  ///
  /// [query] mantiene el orden de inserción, que forma parte del contrato
  /// congelado en los goldens.
  Future<Result<T>> get<T>(
    String action, {
    Map<String, String> query = const {},
    required T Function(Object? data) decode,
  }) {
    final url = StringBuffer('$baseUrl?action=$action');
    for (final entry in query.entries) {
      url.write('&${entry.key}=${entry.value}');
    }
    return _send(
      () => _client.get(Uri.parse(url.toString())).timeout(timeout),
      decode,
    );
  }

  /// POST con la acción en la query string y el cuerpo en JSON.
  Future<Result<T>> post<T>(
    String action, {
    required Map<String, Object?> body,
    required T Function(Object? data) decode,
  }) {
    return _send(
      () => _client
          .post(
            Uri.parse('$baseUrl?action=$action'),
            headers: _jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(timeout),
      decode,
    );
  }

  /// POST con la acción **dentro** del cuerpo, sin query string.
  ///
  /// Tres endpoints lo hacen así (`save_tournament_rules`, `generate_fixture`,
  /// `delete_fixture`). Se conserva tal cual: cambiarlo rompería I2.
  Future<Result<T>> postActionInBody<T>(
    String action, {
    required Map<String, Object?> body,
    required T Function(Object? data) decode,
  }) {
    return _send(
      () => _client
          .post(
            Uri.parse(baseUrl),
            headers: _jsonHeaders,
            body: jsonEncode({'action': action, ...body}),
          )
          .timeout(timeout),
      decode,
    );
  }

  /// POST multipart, para las subidas que llevan el PDF del acta.
  Future<Result<T>> multipart<T>(
    String action, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    required T Function(Object? data) decode,
  }) {
    return _send(() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl?action=$action'),
      );
      request.fields.addAll(fields);
      request.files.addAll(files);
      final streamed = await _client.send(request).timeout(uploadTimeout);
      return http.Response.fromStream(streamed);
    }, decode);
  }

  // ---------------------------------------------------------------------------
  // Envío y traducción de fallos
  // ---------------------------------------------------------------------------

  Future<Result<T>> _send<T>(
    Future<http.Response> Function() perform,
    T Function(Object? data) decode,
  ) async {
    final http.Response response;
    try {
      response = await perform();
    } on TimeoutException catch (e) {
      return Err(RequestTimeoutException(cause: e));
    } catch (e) {
      // ConnectivityHelper ya sabe distinguir un fallo de red del resto.
      if (ConnectivityHelper.isNetworkError(e)) {
        return Err(NetworkException(cause: e));
      }
      return Err(ParseException(cause: e));
    }

    // El backend usa 200 y 201 indistintamente para el camino feliz.
    if (response.statusCode != 200 && response.statusCode != 201) {
      return Err(HttpStatusException(response.statusCode));
    }

    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return Err(ParseException(cause: e));
    }

    if (envelope['status'] != 'success') {
      return Err(
        ApiBusinessException(
          envelope['message']?.toString() ??
              'El servidor rechazó la solicitud.',
        ),
      );
    }

    try {
      return Ok(decode(envelope['data']));
    } catch (e) {
      return Err(ParseException(cause: e));
    }
  }
}
