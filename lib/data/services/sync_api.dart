import '../../core/api/api_client.dart';
import '../models/sync_models.dart';

/// Offline-sync endpoints: the device registry now; heartbeat, catalogue
/// pulls and sale uploads join as the offline mode grows.
class SyncApi {
  SyncApi(this._client);

  final ApiClient _client;

  /// `POST /sync/devices/register`. Safe to repeat: the server upserts the
  /// till by [deviceId].
  Future<Device> registerDevice({
    required String deviceId,
    String? name,
    String? model,
    String? appVersion,
  }) async {
    final json = await _client.post(
      '/sync/devices/register',
      body: {
        'deviceId': deviceId,
        'name': ?name,
        'model': ?model,
        'appVersion': ?appVersion,
      },
    );
    if (json is Map) return Device.fromJson(Map<String, dynamic>.from(json));
    throw const FormatException('Expected a JSON object from the server.');
  }
}
