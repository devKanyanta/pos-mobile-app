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
    return Device.fromJson(_map(json));
  }

  /// `GET /sync/catalog`. Without [since] the server sends everything; with
  /// the previous response's `serverTime` it sends only what changed.
  Future<CatalogSnapshot> fetchCatalog({String? since}) async {
    final json = await _client.get(
      '/sync/catalog',
      query: since == null ? null : {'since': since},
    );
    return CatalogSnapshot.fromJson(_map(json));
  }

  /// `POST /sync/sales`: uploads offline sales. [pendingQueueSize] is how
  /// many are still queued on the device after this batch. Re-sending a sale
  /// the server already has is answered `DUPLICATE`, so retries are safe.
  Future<SyncSalesResponse> uploadSales({
    required String deviceId,
    required int pendingQueueSize,
    required List<OfflineSaleDraft> sales,
  }) async {
    final json = await _client.post(
      '/sync/sales',
      body: {
        'deviceId': deviceId,
        'pendingQueueSize': pendingQueueSize,
        'sales': [for (final sale in sales) sale.toJson()],
      },
    );
    return SyncSalesResponse.fromJson(_map(json));
  }

  /// `POST /sync/heartbeat`: tells the server this till is online and how
  /// many transactions are waiting on it.
  Future<void> heartbeat({
    required String deviceId,
    required int pendingQueueSize,
    required bool online,
    String? appVersion,
  }) async {
    await _client.post(
      '/sync/heartbeat',
      body: {
        'deviceId': deviceId,
        'pendingQueueSize': pendingQueueSize,
        'online': online,
        'appVersion': ?appVersion,
      },
    );
  }

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map) return Map<String, dynamic>.from(json);
    throw const FormatException('Expected a JSON object from the server.');
  }
}
