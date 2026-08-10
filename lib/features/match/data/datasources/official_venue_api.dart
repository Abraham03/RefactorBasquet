import 'package:myapp/core/network/api_actions.dart';
import 'package:myapp/core/network/api_client.dart';
import 'package:myapp/core/network/result.dart';
import 'package:myapp/core/utils/json_parsing.dart';

/// Sedes y oficiales: los catálogos que se administran desde el alta de partido.
///
/// Uno de los cinco datasources en los que se divide `ApiService` (SRP). Todos
/// sus métodos devuelven `Result`, así que el llamador siempre puede distinguir
/// "sin internet" de "el servidor rechazó" de "el JSON venía mal" — algo
/// imposible con el `Future<bool>` que devolvían antes.
class OfficialVenueApi {
  OfficialVenueApi(this._client);

  final ApiClient _client;

  // --- Sedes ---

  Future<Result<int>> createVenue(String name, String address) {
    return _client.post(
      ApiActions.createVenue,
      body: {'name': name, 'address': address},
      decode: (data) => parseId((data! as Map)['newId']),
    );
  }

  Future<Result<void>> updateVenue({
    required String id,
    required String name,
    required String address,
  }) {
    return _client.post(
      ApiActions.updateVenue,
      // `id` viaja como String aquí y como int en delete: así lo espera el
      // backend hoy. Uniformarlo es un cambio de contrato (I2), no de refactor.
      body: {'id': id, 'name': name, 'address': address},
      decode: (_) {},
    );
  }

  Future<Result<void>> deleteVenue(int id) {
    return _client.post(
      ApiActions.deleteVenue,
      body: {'id': id},
      decode: (_) {},
    );
  }

  // --- Oficiales ---

  Future<Result<int>> createOfficial(
    String name,
    String role,
    String? signature,
  ) {
    return _client.post(
      ApiActions.createOfficial,
      body: {'name': name, 'role': role, 'signature': signature},
      decode: (data) => parseId((data! as Map)['id']),
    );
  }

  Future<Result<void>> updateOfficial({
    required String id,
    required String name,
    required String role,
    String? signature,
  }) {
    return _client.post(
      ApiActions.updateOfficial,
      body: {'id': id, 'name': name, 'role': role, 'signature': signature},
      decode: (_) {},
    );
  }

  Future<Result<void>> deleteOfficial(int id) {
    return _client.post(
      ApiActions.deleteOfficial,
      body: {'id': id},
      decode: (_) {},
    );
  }
}
